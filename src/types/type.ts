export interface DecodedModuleBytes {
  address: string
  name: string
  friends: string[]
  exposed_functions: []
  structs: []
}

export interface DecodedScriptBytes {
  name: string
  visibility: string
  is_entry: boolean
  is_view: boolean
  generic_type_params: string[]
  params: string[]
  return: string[]
}

export interface ModuleInfo {
  address: string
  name: string
}
