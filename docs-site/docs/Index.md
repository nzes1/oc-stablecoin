---
hide_title: true
slug: /
hide_table_of_contents: true
pagination_label: 'Home'
---
import DocCardList from '@theme/DocCardList';
import Feature from '@site/src/components/Feature';
import Row from '@site/src/components/Row';
import Hero from '@site/src/components/Hero';
import Link from '@docusaurus/Link';

<head>
  <meta property="og:title" content="DSC Protocol Docs" />
  <meta property="og:image" content="https://nzes1.github.io/oc-stablecoin/img/dsc-protocol-preview.png" />
  <meta property="og:url" content="https://nzes1.github.io/oc-stablecoin/" />
  <meta name="description" content="A comprehensive documentation site for the DSC Protocol, covering design principles, architecture, ABI, and functionalities." />
  <meta property="og:description" content="A comprehensive documentation site for the DSC Protocol, covering design principles, architecture, ABI, and functionalities." />
</head>

<Hero
  background="linear-gradient(135deg,rgb(18, 18, 66) 0%,rgb(33, 36, 44) 100%)"
  textColor="#fff"
  title="Powering Decentralized Stability on Ethereum"
  subtitle="Explore the comprehensive documentation for the DSC Protocol, a robust and overcollateralized stablecoin system built for the Ethereum blockchain. Learn how to mint, manage, and interact with DSC."
  buttons={[
    {
      text: 'Get Started <span aria-hidden="true">→</span>',
      href: 'protocol-overview',
      className: 'button button--primary button--lg',
    },
    {
      text: 'Explore the ABI <span aria-hidden="true">→</span>',
      href: 'Developers/Contracts', 
      className: 'button button--info button--lg',
    },
  ]}
/>

<br />

<h2 style={{ textAlign: 'center', color:'rgb(6, 209, 216)' }}>🔑 Key Features</h2>

<Row>
  <Feature
    title="Decentralized & Trustless"
    description="DSC operates entirely on the Ethereum blockchain, ensuring transparency and eliminating the need for intermediaries. Built with robust smart contracts for secure and verifiable stability."
    icon="🔒"
  />
  <Feature
    title="Overcollateralized Stability"
    description="DSC's peg to the US Dollar is maintained through an overcollateralization mechanism, providing a strong safety net against market volatility and ensuring reliable value."
    icon="🏦"
  />
  <Feature
    title="Seamless Ethereum Integration"
    description="Designed specifically for the Ethereum ecosystem, DSC seamlessly integrates with various DeFi protocols, wallets, and tools."
    icon="🌐"
  />
</Row>

<br />

<h2 style={{ textAlign: 'center', color:'rgb(59, 175, 190)' }}>🚀 Dive Deeper: Explore Key Sections</h2> 

<Row style={{ gap: '20px', rowGap: '20px', flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center' }}>
  <div key="overview" className="homepage-tile">
    <Link to="protocol-overview" className="homepage-tile-link">
      <h3>Protocol Overview</h3>
      <p>Understand the core concepts and design principles behind the DSC Protocol.</p>
      <span className="arrow-icon">→</span>
    </Link>
  </div>
  <div key="collateral" className="homepage-tile">
    <Link to="Collateral Mechanism/Overview" className="homepage-tile-link">
      <h3>Collateral Mechanism</h3>
      <p>Learn about the supported collateral types, risk parameters, and how overcollateralization works.</p>
      <span className="arrow-icon">→</span>
    </Link>
  </div>
  <div key="minting" className="homepage-tile">
    <Link to="category/Minting and Burning DSC" className="homepage-tile-link">
      <h3>Minting & Redeeming DSC</h3>
      <p>Discover the processes for minting DSC by locking collateral and redeeming collateral by burning DSC.</p>
      <span className="arrow-icon">→</span>
    </Link>
  </div>
  <div key="liquidations" className="homepage-tile">
    <Link to="/category/Liquidations" className="homepage-tile-link">
      <h3>Liquidations</h3>
      <p>Understand how the protocol protects itself from undercollateralized vaults through liquidations and the incentives for liquidators.</p>
      <span className="arrow-icon">→</span>
    </Link>
  </div>
  <div key="fees" className="homepage-tile">
    <Link to="Fees" className="homepage-tile-link">
      <h3>Protocol Fees</h3>
      <p>Learn about the different fees associated with using the DSC Protocol, including the continuous protocol fee and the liquidation penalty.</p>
      <span className="arrow-icon">→</span>
    </Link>
  </div>
  {/* Add more div elements with Link for other key sections */}
</Row>

{/* ... rest of your homepage */}

<br />

<!-- ## Ready to Integrate?

Developers can leverage the DSC Protocol to build innovative DeFi applications. Explore our smart contract documentation and interfaces to get started.

<Row style={{ display: 'flex', gap: '20px', justifyContent: 'center' }}>
  <
    text={<>Smart Contract Overview <span aria-hidden="true">→</span></>}
    href="/contracts"
    className="button button--outline button--primary button--lg"
  />
  <Button
    text={<>View on GitHub <span aria-hidden="true">→</span></>}
    href="YOUR_GITHUB_REPO_LINK"
    className="button button--outline button--info button--lg"
  />
</Row> -->

<!-- <br />

<Row style={{ justifyContent: 'center', alignItems: 'center', padding: '2rem 0' }}>
  <p style={{ fontSize: '0.9rem', color: '#a0a0a0', textAlign: 'center' }}>
    © {new Date().getFullYear()} DSC Protocol | Built with Docusaurus 🦖
  </p>
</Row> -->