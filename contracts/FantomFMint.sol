pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./FantomCollateral.sol";
import "./interface/IPriceOracle.sol";
import "./interface/IFantomDeFiTokenRegistry.sol";

// FantomFMint implements the contract of core DeFi function
// for minting tokens against a deposited collateral. The collateral
// management is linked from the Fantom Collateral implementation.
// Minting is burdened with a minting fee defined as the amount
// of percent of the minted tokens value in fUSD. Burning is free
// of any fee.
contract FantomFMint is Ownable, ReentrancyGuard, FantomCollateral {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // feePool keeps information about the fee collected from
    // minter internal operations in fMin fee tokens identified below (fUSD).
    uint256 public feePool;

    // Minted is emitted on confirmed token minting against user's collateral value.
    event Minted(address indexed token, address indexed user, uint256 amount);

    // Repaid is emitted on confirmed token repay of user's debt of the token.
    event Repaid(address indexed token, address indexed user, uint256 amount);

    // -------------------------------------------------------------
    // Price and value calculation related utility functions
    // -------------------------------------------------------------

    // fMintPriceOracle represents the address of the price
    // oracle aggregate used by the collateral to get
    // the price of a specific token.
    address public const fMintPriceOracle = address(0x03AFBD57cfbe0E964a1c4DBA03B7154A6391529b);

    // fTokenRegistry represents the address of the Fantom token
    // registry contract responsible for providing DeFi tokens information.
    address public const fTokenRegistry = address(0x03AFBD57cfbe0E964a1c4DBA03B7154A6391529b);

    // fMintFeeToken represents the identification of the token
    // we use for fee by the fMint DeFi module (fUSD).
    address public const fMintFeeToken = address(0xf15Ff135dc437a2FD260476f31B3547b84F5dD0b);

    // fMintPriceDigitsCorrection represents the correction required
    // for FTM/ERC20 (18 digits) to another 18 digits number exchange
    // through an 8 digits USD (ChainLink compatible) price oracle
    // on any minting price value calculation.
    uint256 public const fMintPriceDigitsCorrection = 100000000;

    // fMintFee represents the current value of the minting fee used
    // for minter operations.
    // The value is kept in 4 decimals; 25 = 0.0025 = 0.25%
    uint256 public const fMintFee = 25;

    // fMintFeeDigitsCorrection represents the value to be used
    // to adjust result decimals after applying fee to a value calculation.
    uint256 public const fMintFeeDigitsCorrection = 10000;

    // -------------------------------------------------------------
    // Minter functions below
    // -------------------------------------------------------------

    // mint allows user to create a specified token against already established
    // collateral. The value of the collateral must be in at least configured
    // ratio to the total user's debt value on minting.
    function mint(address _token, uint256 _amount) external nonReentrant
    {
        // make sure the debt amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // native tokens can not be minted
        require(_token != fMintNativeToken(), "native tokens not mintable");

        // make sure there is some collateral established by this user
        // we still need to re-calculate the current value though, since the value
        // could have changed due to exchange rate fluctuation
        require(_collateralValue[msg.sender] > 0, "missing collateral");

        // what is the value of the borrowed token?
        uint256 tokenValue = IPriceOracle(fMintPriceOracle).getPrice(_token);
        require(tokenValue > 0, "token has no value");

        // calculate the minting fee and store the value we gained by this operation
        uint256 fee = _amount
                        .mul(tokenValue)
                        .mul(fMintFee)
                        .div(fMintFeeDigitsCorrection)
                        .div(fMintPriceDigitsCorrection);
        feePool = feePool.add(fee);

        // register the debt of the fee in the fee token
        _debtByTokens[fMintFeeToken][msg.sender] = _debtByTokens[fMintFeeToken][msg.sender].add(fee);
        _debtByUsers[msg.sender][fMintFeeToken] = _debtByUsers[msg.sender][fMintFeeToken].add(fee);
        enrolDebt(fMintFeeToken, msg.sender);

        // register the debt of minted token
        _debtByTokens[_token][msg.sender] = _debtByTokens[_token][msg.sender].add(_amount);
        _debtByUsers[msg.sender][_token] = _debtByUsers[msg.sender][_token].add(_amount);
        enrolDebt(_token, msg.sender);

        // recalculate current collateral and debt values
        uint256 cCollateralValue = collateralValue(msg.sender);
        uint256 cDebtValue = debtValue(msg.sender);

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue
                                        .mul(collateralLowestDebtRatio4dec)
                                        .div(collateralRatioDecimalsCorrection());

        // does the new state obey the enforced minimal collateral to debt ratio?
        require(cCollateralValue >= minCollateralValue, "insufficient collateral");

        // update the current collateral and debt value
        _collateralValue[msg.sender] = cCollateralValue;
        _debtValue[msg.sender] = cDebtValue;

        // mint the requested balance for the ERC20 tokens to cover the transfer
        // NOTE: the local address has to have the minter privilege
        ERC20Mintable(_token).mint(address(this), _amount);

        // transfer minted tokens to the user address
        ERC20(_token).safeTransfer(msg.sender, _amount);

        // emit the minter notification event
        emit Minted(_token, msg.sender, _amount, block.timestamp);
    }

    // repay allows user to return some of the debt of the specified token
    // the repay does not collect any fees and is not validating the user's total
    // collateral to debt position.
    function repay(address _token, uint256 _amount) external nonReentrant
    {
        // make sure the amount repaid makes sense
        require(_amount > 0, "non-zero amount expected");

        // native tokens can not be minted through this contract
        // so there can not be any debt to be repaid on them
        require(_token != fMintNativeToken(), "native tokens not mintable");

        // subtract the returned amount from the user debt
        _debtByTokens[_token][msg.sender] = _debtByTokens[_token][msg.sender].sub(_amount, "insufficient debt outstanding");
        _debtByUsers[msg.sender][_token] = _debtByUsers[msg.sender][_token].sub(_amount, "insufficient debt outstanding");

        // update current collateral and debt amount state
        _collateralValue[msg.sender] = collateralValue(msg.sender);
        _debtValue[msg.sender] = debtValue(msg.sender);

        // burn the tokens returned by the user
        // NOTE: Allowance must be granted by the tokens owner before to allow the burning
        ERC20Burnable(_token).burnFrom(msg.sender, _amount);

        // emit the repay notification
        emit Repaid(_token, msg.sender, _amount, block.timestamp);
    }
}
