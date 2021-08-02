const { deployProxy, upgradeProxy, prepareUpgrade } = require('@openzeppelin/truffle-upgrades');

var FantomLiquidationManager = artifacts.require("../contracts/liquidator/FantomLiquidationManager.sol");

module.exports = async function(deployer) {
	const fantomLiquidationManager = await deployProxy(FantomLiquidationManager, ["0xe8A06462628b49eb70DBF114EA510EB3BbBDf559", "0xcb20a1A22976764b882C2f03f0C8523F3df54b10"], { deployer });
}