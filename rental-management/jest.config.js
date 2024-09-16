module.exports = {
    preset: '@vue/cli-plugin-unit-jest',
    transform: {
      '^.+\\.vue$': 'vue-jest',
      '^.+\\js$': 'babel-jest',
    },
    moduleFileExtensions: ['js', 'json', 'vue'],
    transformIgnorePatterns: ['<rootDir>/node_modules/'],
  };
  