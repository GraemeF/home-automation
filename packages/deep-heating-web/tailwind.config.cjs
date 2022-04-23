module.exports = {
  content: ['./src/**/*.{html,js,svelte,ts}'],
  theme: {
    colors: {
      heating: '#FF9700',
      cooling: '#77DAE8',
    },
    extend: {},
  },
  plugins: [require('daisyui')],
};
