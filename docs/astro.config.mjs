// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://0xveya.github.io',
	base: '/dogshitnorm.nvim/',
	integrations: [
		starlight({
			title: 'dogshitnorm.nvim',
			description: '42-focused Neovim tooling for norminette, headers, and Makefiles.',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/0xveya/dogshitnorm.nvim' }],
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Overview', slug: '' },
						{ label: 'Getting Started', slug: 'guides/getting-started' },
						{ label: 'Headers', slug: 'guides/headers' },
						{ label: 'Makefiles', slug: 'guides/makefiles' },
					],
				},
				{
					label: 'Reference',
					autogenerate: { directory: 'reference' },
				},
			],
		}),
	],
});
