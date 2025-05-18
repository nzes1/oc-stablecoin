import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  
  mainSidebar: [
    {
      type: 'link',
      label: 'Homepage',
      href: '/',
    },
    'protocol-overview',
    {
      type: 'category',
      label: 'Collateral Mechanism',
      items: [
        'Collateral Mechanism/Overview',
        'Collateral Mechanism/Design',
        'Collateral Mechanism/Types & Configuration',
        'Collateral Mechanism/Config & Risk Parameters',
        'Collateral Mechanism/Collateral Management Interface',
      ],
      link: {
        type: 'doc',
        id: 'Collateral Mechanism/Overview',
      }
    },
    {
      type: 'category',
      label: 'Minting and Burning DSC',
      items: [
        'Minting and Burning DSC/DSC Token',
        'Minting and Burning DSC/Minting-Redeeming'
      ],
      link: {
        type: 'generated-index',
        slug: 'category/Minting and Burning DSC'
      }
    },
    {
      type: 'category',
      label: 'Liquidations',
      items: [
        'Liquidations/Understanding Liquidations',
        'Liquidations/Rewards Mechanism',
        'Liquidations/Liquidation Interface Functions',
      ],
      link: {
        type: 'generated-index',
        slug: '/category/Liquidations',
      }
    },
    'Fees',
    {
      type: 'category',
      label: 'Developers',
      items: [
        'Developers/Contracts',
      ]
    },
  ],
   
};

export default sidebars;
