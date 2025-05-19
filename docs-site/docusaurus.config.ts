import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';

const config: Config = {
  title: 'DSC Protocol Docs',
  tagline: 'Powering Decentralized Stability on Ethereum',
  favicon: 'img/favicon.ico',

  url: 'https://nzes1.github.io/',
  baseUrl: '/oc-stablecoin/',
  deploymentBranch: 'gh-pages',

  organizationName: 'nzes1',
  projectName: 'docusaurus',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  stylesheets: [
    {
      href: 'https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css',
      type: 'text/css',
      integrity:
        'sha384-姒fGOMR/kWVcvrzHPDfN/z6UUcvzj9cB+F0n2+znlBt2Y1nZlNRW9FmiTgRgoaa',
      crossorigin: 'anonymous',
    },
  ],

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          //editUrl:
          //  'https://github.com/facebook/docusaurus/tree/main/packages/create-docusaurus/templates/shared/',
          remarkPlugins: [remarkMath],
          rehypePlugins: [rehypeKatex],
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/dsc-protocol-preview.png',
    navbar: {
      title: 'DSC Protocol',
      logo: {
        alt: 'DSC Protocol Logo',
        src: 'img/dsc-logo.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'mainSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://github.com/nzes1/oc-stablecoin',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Community',
          items: [
            {
              label: 'Discord',
              href: 'https://discord.gg/FBB2AfbrKR',
            },
            {
              label: 'X',
              href: 'https://x.com/nzesi_eth',
            },
          ],
        },
        {
          title: 'Social',
          items: [
            {
              label: 'LinkedIn',
              href: 'https://linkedin.com/in/simon-mutua',
            },
            {
              label: 'GitHub',
              href: 'https://github.com/nzes1',
            },
          ],
        },
      ],
      copyright: `DSC Protocol. Built with ❤️ and <a href="https://docusaurus.io/" target="_blank" rel="noopener noreferrer">Docusaurus</a>. <br/> Copyright © ${new Date().getFullYear()} DSC Protocol.`,
    },
    prism: {
      theme: prismThemes.nightOwl,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['solidity'],
    },
    
  } satisfies Preset.ThemeConfig,
};

export default config;