pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

// FantomLiquidationManager implements the liquidation model
// with the ability to fine tune settings by the contract owner.
contract FantomLiquidationManager is Initializable, Ownable
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;

    struct VaultData {
        address liquidator;
        uint256 liquidationPenalty;
        uint256 maxAmt;
        uint256 targetAmt;
    }

    // mapping(address => mapping(address => uint256)) public liquidatedVault;
    mapping(address => uint256) public admins;
    mapping(bytes32 => VaultData) public vaultDatas;

    uint256 public live;
    uint256 public maxAmt;
    uint256 public targetAmt;

    // initialize initializes the contract properly before the first use.
    function initialize(address owner) public initializer {
        // initialize the Ownable
        Ownable.initialize(owner);

        // initialize default values
        admins[owner] = 1;
        live = 1;
    }

    function addAdmin(address usr) external onlyOwner {
        admins[usr] = 1;
    }

    function removeAdmin(address usr) external onlyOwner {
        admins[usr] = 0;
    }

    modifier auth {
        require(admins[msg.sender] == 1, "Sender not authorized");
        _;
    }

    function startLiquidation(bytes32 vaultIndex, address urn, address rewardReceiver) external returns (uint256 id) {
        require(live == 1, "Liquidation not live");

        (uint256 lockedCollat, uint256 normalisedDebt) = vat.urns(vaultIndex, urn);
        VaultData memory mVaultData = vaultDatas[vaultIndex];
        uint256 dNormalisedDebt;
        uint256 rate;
        uint256 dust;

        // dart calculation
        uint256 spot;
        (, rate, spot,, dust) = vat.ilks(vaultIndex);
        require(spot > 0 && mul(ink, spot) < mul(art, rate), "Collateral not unsafe");

        require(maxAmt > targetAmt && mVaultData.maxAmt > mVaultData.targetAmt, "Collateral liquidation limit hit");
        uint256 room = min(maxAmt - targetAmt, mVaultData.maxAmt - mVaultData.targetAmt);

        // dNormalisedDebt = min(normalisedDebt, )
    }

    function endLiquidation() external auth {
        live = 0;
    }
}
