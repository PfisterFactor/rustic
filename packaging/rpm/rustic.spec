%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           rustic
Version:        %{_version}
Release:        0.%{_buildnum}.git%{_shortsha}%{?dist}
Summary:        Fast, encrypted, deduplicated backups powered by Rust
License:        Apache-2.0 OR MIT
URL:            https://github.com/%{_owner}/rustic
ExclusiveArch:  x86_64 aarch64

Source0:        rustic
Source1:        LICENSE-APACHE
Source2:        LICENSE-MIT

%description
rustic is a backup tool that provides fast, encrypted, deduplicated backups.
It reads and writes the restic repository format and can be used as a
restic replacement in most cases.

%prep

%build

%install
install -D -m 0755 %{SOURCE0} %{buildroot}%{_bindir}/rustic
install -D -m 0644 %{SOURCE1} %{buildroot}%{_defaultlicensedir}/%{name}/LICENSE-APACHE
install -D -m 0644 %{SOURCE2} %{buildroot}%{_defaultlicensedir}/%{name}/LICENSE-MIT

%files
%license %{_defaultlicensedir}/%{name}/LICENSE-APACHE
%license %{_defaultlicensedir}/%{name}/LICENSE-MIT
%{_bindir}/rustic

%changelog
* %{_changelog_date} PfisterFactor Fork <noreply@github.com> - %{version}-%{release}
- Automated build from commit %{_shortsha}
