export interface BuildOptions {
  /**
   * Compile in 'dev' mode. The 'dev-addresses' and 'dev-dependencies' fields will be used if
   * this flag is set. This flag is useful for development of packages that expose named
   * addresses that are not set to a specific value.
   */
  devMode?: boolean

  /**
   * Compile in 'test' mode. The 'dev-addresses' and 'dev-dependencies' fields will be used
   * along with any code in the 'tests' directory.
   */
  testMode?: boolean

  /**
   * Generate documentation for packages.
   */
  generateDocs?: boolean

  /**
   * Generate ABIs for packages.
   */
  generateAbis?: boolean

  /**
   * Installation directory for compiled artifacts. Defaults to current directory.
   */
  installDir?: string

  /**
   * Force recompilation of all packages.
   */
  forceRecompilation?: boolean

  /**
   * Only fetch dependency repos to MOVE_HOME.
   */
  fetchDepsOnly?: boolean

  /**
   * Skip fetching latest git dependencies.
   */
  skipFetchLatestGitDeps?: boolean

  /**
   * Bytecode version. Set to 0 to unset and use default.
   */
  bytecodeVersion?: number

  /**
   * Compiler version. Set to 0 to unset and use default.
   */
  compilerVersion?: string

  /**
   * Language version. Set to 0 to unset and use default.
   */
  languageVersion?: string

  /**
   * Additional named address mapping. Useful for tools in Rust.
   */
  addtionalNamedAddresses?: [string, string][]
}

export interface CleanOptions {
  /**
   * Flush cache directory.
   */
  cleanCache?: boolean

  /**
   * Flush other byproducts from compiler. It only removes files and directories with default name.
   */
  cleanByProduct?: boolean

  /**
   * Don't ask before commit.
   */
  force?: boolean
}

export interface TestOptions {
  /**
   * A filter string to determine which unit tests to run. A unit test will be run only if it
   * contains this string in its fully qualified (<addr>::<module_name>::<fn_name>) name.
   */
  filter?: string

  /**
   * Report test statistics at the end of testing.
   */
  reportStatistics?: boolean

  /**
   * Show the storage state at the end of execution of a failing test.
   */
  reportStorageOnError?: boolean

  /**
   * Ignore compiler's warning, and continue run tests.
   */
  ignoreCompileWarnings?: boolean

  /**
   * Collect coverage information for later use with the various `package coverage` subcommands.
   */
  computeCoverage?: boolean
}
