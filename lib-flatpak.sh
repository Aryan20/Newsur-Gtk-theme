# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

die() {
  echo "$@" >&2
  exit 1
}

pakitheme_gtk3() {
  local color="$(destify ${1})"
  local opacity="$(destify ${2})"
  local alt="$(destify ${3})"
  local theme="$(destify ${4})"

  local FLATPAK_THEME="${name}${color}${opacity}${alt}${theme}"

  local GTK_3_THEME_VER=3.22
  local cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local pakitheme_cache="$cache_home/pakitheme"
  local repo_dir="$pakitheme_cache/repo"
  local gtk3_app_id="org.gtk.Gtk3theme.$FLATPAK_THEME"
  local root_dir="$pakitheme_cache/$FLATPAK_THEME"
  local repo_dir="$root_dir/repo"
  local build_dir="$root_dir/build"

  for location in "$data_home/themes" "$HOME/.themes" /usr/share/themes; do
    if [[ -d "$location/$FLATPAK_THEME" ]]; then
      prompt -s "Found theme located at: $location/$FLATPAK_THEME \n"
      theme_path="$location/$FLATPAK_THEME"
      break
    fi
  done

  if [[ -n "$theme_path" ]]; then
    prompt -i "Converting theme: $FLATPAK_THEME... \n"
  else
    prompt -e "Could not locate theme... install theme first! \n"
    exit 0
  fi

  rm -rf "$root_dir" "$repo_dir"
  mkdir -p "$repo_dir"
  ostree --repo="$repo_dir" init --mode=archive
  ostree --repo="$repo_dir" config set core.min-free-space-percent 0

  rm -rf "$build_dir"
  mkdir -p "$build_dir/files"

  theme_gtk_version=$(ls -1d "$theme_path"/* 2>/dev/null | grep -Po 'gtk-3\.\K\d+$' | sort -nr | head -1)
  [[ -n "$theme_gtk_version" ]] || \
    die "Theme directory did not contain any recognized GTK themes."

  cp -a "$theme_path/gtk-3.$theme_gtk_version/"* "$build_dir/files"

  mkdir -p "$build_dir/files/share/appdata"
  cat >"$build_dir/files/share/appdata/$gtk3_app_id.appdata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="runtime">
  <id>$gtk3_app_id</id>
  <metadata_license>CC0-1.0</metadata_license>
  <name>$FLATPAK_THEME Gtk theme</name>
  <summary>$FLATPAK_THEME Gtk theme (generated via pakitheme)</summary>
</component>
EOF

  appstream-compose --prefix="$build_dir/files" --basename="$gtk3_app_id" --origin=flatpak "$gtk3_app_id"

  ostree --repo="$repo_dir" commit -b base --tree=dir="$build_dir"

  bundles=()

  while read -r arch; do
    bundle="$root_dir/$gtk3_app_id-$arch.flatpak"

    rm -rf "$build_dir"
    ostree --repo="$repo_dir" checkout -U base "$build_dir"

    read -rd '' metadata <<EOF ||:
[Runtime]
name=$gtk3_app_id
runtime=$gtk3_app_id/$arch/$GTK_3_THEME_VER
sdk=$gtk3_app_id/$arch/$GTK_3_THEME_VER
EOF
    # Make sure there is no trailing newline, so xa.metadata doesn't get confused later
    echo -n "$metadata" > "$build_dir/metadata"

    ostree --repo="$repo_dir" commit -b "runtime/$gtk3_app_id/$arch/$GTK_3_THEME_VER" \
      --add-metadata-string "xa.metadata=$(cat $build_dir/metadata)" --link-checkout-speedup "$build_dir"
    flatpak build-bundle --runtime "$repo_dir" "$bundle" "$gtk3_app_id" "$GTK_3_THEME_VER"

    trap 'rm "$bundle"' EXIT

    bundles+=("$bundle")
    # Note: a pipe can't be used because it will mess with subshells and cause the append
    # to bundles to fail.
  done < <(flatpak list --runtime --columns=arch:f | sort -u)

  for bundle in "${bundles[@]}"; do
    if [[ -w "/root" ]]; then
      sudo flatpak install -y --system "${bundle}"
    else
      udo flatpak install -y --user "${bundle}"
    fi
  done
}

flatpak_remove() {
  local color="$(destify ${1})"
  local opacity="$(destify ${2})"
  local alt="$(destify ${3})"
  local theme="$(destify ${4})"

  if [[ -w "/root" ]]; then
    sudo flatpak remove -y --system org.gtk.Gtk3theme.${name}${color}${opacity}${alt}${theme}
  else
    udo flatpak remove -y --user org.gtk.Gtk3theme.${name}${color}${opacity}${alt}${theme}
  fi
}
