# The base profile should include component modules that will be on all nodes
class profile::base {
  if $facts['kernel'] == 'windows' {
    include scm_window
  } else {
    include scm_linux
  }
}
