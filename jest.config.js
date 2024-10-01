module.exports = {
  testEnvironment: 'node',
  preset: 'ts-jest',
  roots: ['<rootDir>/src'],
  globals: {
    'ts-jest': {
      isolatedModules: true,
    },
  },
}
