module.exports = {
    networks: {
        development: {
            host: "operavm",
            port: 7545,
            network_id: "4002"
        },
        test: {
            host: "wsapi.testnet.fantom.network",
            port: 80,
            network_id: "4002"
        }
    }
};
