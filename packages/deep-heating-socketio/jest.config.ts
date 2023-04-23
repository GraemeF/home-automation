/* eslint-disable */
export default {
  displayName: 'deep-heating-socketio',

  globals: {},
  testEnvironment: 'node',
  transform: {
    '^.+\\.[tj]s$': [
      'ts-jest',
      {
        tsconfig: '<rootDir>/tsconfig.spec.json',
      },
    ],
  },
  moduleFileExtensions: ['ts', 'js', 'html'],
  coverageDirectory: '../../coverage/packages/deep-heating-socketio',
  preset: '../../jest.preset.js',
};
