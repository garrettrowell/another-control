# class growell_patch::wu
class growell_patch::wu () {
  file { 'C:\\Program Files\\WindowsPowerShell\\Modules\\PSWindowsUpdate':
    ensure             => directory,
    recurse            => true,
    source_permissions => ignore,
    source             => "puppet:///modules/${module_name}",
  }
  -> file { 'C:\\ProgramData\\InstalledUpdates':
    ensure             => directory,
    recurse            => true,
    source_permissions => ignore,
  }
}
