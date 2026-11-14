# dmgbuild settings for Glint
# Usage: ./make-dmg.sh
app = "Glint.app"

files = [app]
symlinks = {"Applications": "/Applications"}

icon = "Resources/Glint.icns"
background = "Resources/dmg-background.png"

volume_name = "Glint 1.1"
format = "UDZO"

window_rect = ((180, 180), (700, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_offset = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 120
show_icon_preview = False

icon_locations = {
    "Glint.app": (190, 220),
    "Applications": (510, 220),
}

