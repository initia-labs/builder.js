module.exports = {
  testEnvironment: 'node',
  preset: 'ts-jest',
  roots: ['<rootDir>/test'],
  moduleNameMapper: {
    '^builder': '<rootDir>/src/builder.ts',
    '^types$': '<rootDir>/src/types',
    '^lib$': '<rootDir>/src/lib',
  }
}
