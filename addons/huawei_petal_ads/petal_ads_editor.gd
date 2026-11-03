@tool
extends EditorPlugin
## Registers the Android export hook for Huawei Petal Ads.


var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
    _export_plugin = preload("res://addons/huawei_petal_ads/export_plugin.gd").new()
    add_export_plugin(_export_plugin)


func _exit_tree() -> void:
    if _export_plugin != null:
        remove_export_plugin(_export_plugin)
    _export_plugin = null
