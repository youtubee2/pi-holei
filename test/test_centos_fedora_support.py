import pytest
from .conftest import (
    tick_box,
    info_box,
    cross_box,
    mock_command,
)


def mock_selinux_config(state, Pihole):
    '''
    Creates a mock SELinux config file with expected content
    '''
    # validate state string
    valid_states = ['enforcing', 'permissive', 'disabled']
    assert state in valid_states
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': (state.capitalize(), '0')}, Pihole)
    # create mock configuration with desired content
    Pihole.run('''
    mkdir /etc/selinux
    echo "SELINUX={state}" > /etc/selinux/config
    '''.format(state=state.lower()))


@pytest.mark.parametrize("tag", [('centos'), ('fedora'), ])
def test_selinux_enforcing_exit(Pihole):
    '''
    confirms installer prompts to exit when SELinux is Enforcing by default
    '''
    mock_selinux_config("enforcing", Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = cross_box + ' Current SELinux: Enforcing'
    assert expected_stdout in check_selinux.stdout
    expected_stdout = 'SELinux Enforcing detected, exiting installer'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 1


@pytest.mark.parametrize("tag", [('centos'), ('fedora'), ])
def test_selinux_permissive(Pihole):
    '''
    confirms installer continues when SELinux is Permissive
    '''
    mock_selinux_config("permissive", Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = tick_box + ' Current SELinux: Permissive'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


@pytest.mark.parametrize("tag", [('centos'), ('fedora'), ])
def test_selinux_disabled(Pihole):
    '''
    confirms installer continues when SELinux is Disabled
    '''
    mock_selinux_config("disabled", Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = tick_box + ' Current SELinux: Disabled'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


@pytest.mark.parametrize("tag", [('fedora'), ])
def test_epel_and_remi_not_installed_fedora(Pihole):
    '''
    confirms installer does not attempt to install EPEL/REMI repositories
    on Fedora
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    assert distro_check.stdout == ''

    epel_package = Pihole.package('epel-release')
    assert not epel_package.is_installed
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_release_supported_version_check_centos(Pihole):
    '''
    confirms installer exits on unsupported releases of CentOS
    '''
    # modify /etc/redhat-release to mock an unsupported CentOS release
    Pihole.run('echo "CentOS Linux release 6.9" > /etc/redhat-release')
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = cross_box + (' CentOS 6 is not supported.')
    assert expected_stdout in distro_check.stdout
    expected_stdout = 'Please update to CentOS release 7 or later'
    assert expected_stdout in distro_check.stdout


@pytest.mark.parametrize("tag", [('centos'), ])
def test_enable_epel_repository_centos(Pihole):
    '''
    confirms the EPEL package repository is enabled when installed on CentOS
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' Enabling EPEL package repository '
                                  '(https://fedoraproject.org/wiki/EPEL)')
    assert expected_stdout in distro_check.stdout
    expected_stdout = tick_box + ' Installed epel-release'
    assert expected_stdout in distro_check.stdout
    epel_package = Pihole.package('epel-release')
    assert epel_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_php_upgrade_default_optout_centos(Pihole):
    '''
    confirms the default behavior to opt-out of installing PHP7 from REMI
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_php_upgrade_user_optout_centos(Pihole):
    '''
    confirms installer behavior when user opt-out of installing PHP7 from REMI
    (php not currently installed)
    '''
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Pihole)
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_php_upgrade_user_optin_centos(Pihole):
    '''
    confirms installer behavior when user opt-in to installing PHP7 from REMI
    (php not currently installed)
    '''
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    assert 'opt-out' not in distro_check.stdout
    expected_stdout = info_box + (' Enabling Remi\'s RPM repository '
                                  '(https://rpms.remirepo.net)')
    assert expected_stdout in distro_check.stdout
    expected_stdout = tick_box + (' Remi\'s RPM repository has '
                                  'been enabled for PHP7')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_php_version_lt_7_detected_upgrade_default_optout_centos(Pihole):
    '''
    confirms the default behavior to opt-out of upgrading to PHP7 from REMI
    '''
    # first we will install the default php version to test installer behavior
    php_install = Pihole.run('yum install -y php')
    assert php_install.rc == 0
    php_package = Pihole.package('php')
    default_centos_php_version = php_package.version.split('.')[0]
    if int(default_centos_php_version) >= 7:  # PHP7 is supported/recommended
        pytest.skip("Test deprecated . Detected default PHP version >= 7")
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_php_version_lt_7_detected_upgrade_user_optout_centos(Pihole):
    '''
    confirms installer behavior when user opt-out to upgrade to PHP7 via REMI
    '''
    # first we will install the default php version to test installer behavior
    php_install = Pihole.run('yum install -y php')
    assert php_install.rc == 0
    php_package = Pihole.package('php')
    default_centos_php_version = php_package.version.split('.')[0]
    if int(default_centos_php_version) >= 7:  # PHP7 is supported/recommended
        pytest.skip("Test deprecated . Detected default PHP version >= 7")
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Pihole)
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_php_version_lt_7_detected_upgrade_user_optin_centos(Pihole):
    '''
    confirms installer behavior when user opt-in to upgrade to PHP7 via REMI
    '''
    # first we will install the default php version to test installer behavior
    php_install = Pihole.run('yum install -y php')
    assert php_install.rc == 0
    php_package = Pihole.package('php')
    default_centos_php_version = php_package.version.split('.')[0]
    if int(default_centos_php_version) >= 7:  # PHP7 is supported/recommended
        pytest.skip("Test deprecated . Detected default PHP version >= 7")
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    install_dependent_packages PIHOLE_WEB_DEPS[@]
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout not in distro_check.stdout
    expected_stdout = info_box + (' Enabling Remi\'s RPM repository '
                                  '(https://rpms.remirepo.net)')
    assert expected_stdout in distro_check.stdout
    expected_stdout = tick_box + (' Remi\'s RPM repository has '
                                  'been enabled for PHP7')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert remi_package.is_installed
    updated_php_package = Pihole.package('php')
    updated_php_version = updated_php_package.version.split('.')[0]
    assert int(updated_php_version) == 7
