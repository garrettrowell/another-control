# @summary A short summary of the purpose of this class
#
# A description of what this class does
#
# @example
#   include growell_patch
class growell_patch {
  $test = growell_patch::patchday('Tuesday', 2, 4)
  notify { "patchday: ${test}": }

  class { 'patching_as_code':
    classify_pe_patch => true
  }
}
