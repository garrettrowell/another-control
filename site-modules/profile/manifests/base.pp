# The base profile should include component modules that will be on all nodes
class profile::base {
  if $facts['kernel'] == 'windows' {
    include sce_windows
  } else {
    include sce_linux
  }
}
