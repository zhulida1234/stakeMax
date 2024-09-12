require("@nomicfoundation/hardhat-foundry");
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  networks:{
    local: {
      url: 'http://127.0.0.1:8545',
      accounts: [process.env.LOCAL_PRIVATE_KEY]
    }

  }
    
  


};
