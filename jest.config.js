module.exports = {
  testEnvironment: 'node',
  preset: 'ts-jest',
  roots: ['<rootDir>/test'],
  moduleNameMapper: {
    '^build$': '<rootDir>/src/build.ts',
    '^types$': '<rootDir>/src/types',
    '^lib$': '<rootDir>/src/lib',
  }
}
