# 🔥 DSC Protocol: Decentralized Stability on Ethereum 🔥

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-blueviolet.svg)](https://book.getfoundry.sh/)
[![Docs](https://img.shields.io/badge/Documentation-Live%20Soon-brightgreen)](YOUR_DOCS_GITHUB_PAGES_LINK_HERE)
[![Deploy DSC Docs](https://github.com/nzes1/oc-stablecoin/actions/workflows/deploy-docs.yml/badge.svg)](https://github.com/nzes1/oc-stablecoin/actions/workflows/deploy-docs.yml)
[![Twitter](https://img.shields.io/badge/Follow%20me%20on-X-blue?style=social)](https://x.com/nzesi_eth)
[![Discord](https://img.shields.io/badge/Chat%20on-Discord-7289DA?style=social)](https://discord.gg/FBB2AfbrKR)

---


## 🚀 Overview

The DSC Protocol is a cutting-edge, overcollateralized stablecoin protocol built on the Ethereum blockchain. It enables users to generate DSC, a stablecoin pegged to the US dollar, by locking up a variety of whitelisted collateral assets. The protocol prioritizes decentralization, transparency, and robust mechanisms to maintain DSC's stability.

For a deep dive into the design principles, architecture, and detailed explanations of the protocol's functionalities, please refer to the comprehensive documentation: [**[Official Documentation]**](https://nzes1.github.io/oc-stablecoin/).

## ✨ Key Highlights of DSC Protocol

* **Overcollateralization:** DSC is backed by a surplus of collateral, providing a strong safety net against market volatility and ensuring its peg stability.
* **Decentralized Governance:** The protocol is designed with future decentralized governance in mind, allowing the community to shape its evolution.
* **Multi-Collateral Support:** The protocol supports a diverse range of carefully vetted collateral assets, enhancing its resilience and user flexibility.
* **Stability Mechanisms:** Robust mechanisms, including dynamic stability fees and potential liquidations, are in place to maintain DSC's peg to USD.
* **Transparency:** All transactions and collateralization ratios are transparently recorded on the Ethereum blockchain.

## 🛠️ Development Setup (Built with Foundry)

This project leverages the blazing-fast and developer-friendly [Foundry](https://book.getfoundry.sh/) framework for smart contract development, testing, and deployment.

### Prerequisites

Make sure you have Foundry installed on your system. Follow the installation instructions in the [Foundry Book](https://book.getfoundry.sh/getting-started/installation).

### Getting Started

1.  **Clone the repository:**
    ```bash
    git clone [YOUR_GITHUB_REPOSITORY_URL_HERE]
    cd dsc-protocol
    ```

2.  **Install dependencies:**
    ```bash
    forge install
    ```

### Running Tests

To ensure the integrity and correctness of the smart contracts, run the comprehensive test suite:

```bash
forge test
```

### Deploying to a Testnet

Developers looking to deploy DSC Protocol contracts to a testnet (e.g., Sepolia) can leverage Foundry's secure and efficient secret management.

1.  **Securely Manage Your Private Key with a Keystore:** Foundry strongly recommends using an encrypted keystore file to protect your private key. This method avoids exposing your key directly in scripts or environment variables.

    >**Avoid hardcoding your private key in scripts or configuration files such as the `.env`.**

      * **Create a New Keystore (*If you don't have an existing private key you want to use*)**

        ```bash
        cast wallet new --password <your_password> --path ./keystore/<your_wallet_name>.json
        ```

        * Replace `<your_password>` with a strong password.
        * Replace `<your_wallet_name>` with a descriptive name for your wallet (e.g., `sepolia_deployer`). 
        * This command creates a keystore file in the `./keystore/` directory.

      * **Import Your Existing Private Key into a Keystore (*If you have an existing private key you want to use*)**

        ```bash
        cast wallet import <your_wallet_name> --interactive --keystore ./keystore/<your_wallet_name>.json
        ```

          * Replace `<your_wallet_name>` with a descriptive name.
          * The `--interactive` flag prompts you to securely enter your private key.
          * The `--keystore` flag specifies the path to your keystore file. You will be prompted to create and confirm a password to encrypt the key within this file.

2.  **Set up Your Testnet RPC URL:** Store your testnet RPC URL in a `.env` file for easy management.

      * Create a `.env` file in your project root (if it doesn't exist).

      * Add your RPC URL:

        ```
        TESTNET_RPC_URL="YOUR_TESTNET_RPC_URL"
        ```

      * Ensure `.env` is in your `.gitignore`.

      * Load the environment variable in your terminal:

        ```bash
        source .env
        ```

3.  **Run the Deployment Script:** Foundry provides powerful scripting capabilities. You'll find deployment scripts in the `script` folder of the project. Adapt the existing scripts or create new ones for your specific deployment needs

      * **Deploying with a Keystore File**

        ```bash
        forge script script/DeployDSC.s.sol:DeployDSC --rpc-url $TESTNET_RPC_URL --account <your_wallet_name> --keystore ./keystore/<your_wallet_name>.json --broadcast -vvvv
        ```

          * Replace `script/DeployDSC.s.sol:DeployDSC` with the correct path and contract name of your deployment script.
          * Replace `<your_wallet_name>` with the name you used when creating or importing your keystore.
          * You will be prompted to enter the password for your keystore file.

**Important Security Pledge:**

[![Cyfrin Pledge](https://img.shields.io/badge/CYFRIN-green?style=for-the-badge&logo=none&logoColor=white)](https://github.com/Cyfrin/foundry-full-course-cu/discussions/5)[![Stop .env Keys](https://img.shields.io/badge/STOP%20.ENV%20KEYS-orange?style=for-the-badge&logo=none&logoColor=white)](https://github.com/Cyfrin/foundry-full-course-cu/discussions/5)

The Cyfrin team, (of course, from the alpha himself - Patrick!), has strongly advocated against storing private keys in `.env` files due to the inherent security risks. Their discussion on this topic provides valuable context and reinforces the importance of secure key management practices like using Foundry's keystore. You can read more about their pledge and the reasoning behind it [here](https://github.com/Cyfrin/foundry-full-course-cu/discussions/5).

> There is also a YT video showcasing this recommendation - done by Patrick himself [**NEVER use a .env file again | Send this to your foundry friends to keep them safe**](https://www.youtube.com/watch?v=VQe7cIpaE54)

>**TIP**
>
>Always prioritize the security of your private keys. Using dedicated keystore files managed by Foundry is the recommended and most secure method for handling private keys, ensuring they are encrypted and not directly exposed.
>
>

## 🙏 Acknowledgements

I would like to extend my sincere gratitude to the following for their inspiration and the resources that contributed to this project:

* [![Cyfrin Updraft](https://img.shields.io/badge/Inspired%20by-Cyfrin%20Updraft-greenviolet)](https://twitter.com/UpdraftCyfrin) - This project was inspired by the insightful coursework provided by [**Cyfrin Updraft**](https://updraft.cyfrin.io/).

* **Patrick Collins:** - A special thank you to Patrick Collins, the Alpha Tutor from Cyfrin Updraft, for his exceptional educational content and guidance. Follow him on X and subscribe to his Youtube Channel linked below. <br> [![Patrick Collins on Twitter](https://img.shields.io/twitter/follow/patrickalphac?style=social)](https://twitter.com/patrickalphac) [![Patrick Collins on YouTube](https://img.shields.io/badge/YouTube-red?style=for-the-badge&logo=youtube&logoColor=white)](https://www.youtube.com/@PatrickAlphaC)

-----