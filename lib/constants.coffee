module.exports =
    ASSET_DIR_NAME: ".code-annotations"
    ASSET_NAMES_FILE: ".names.cson"
    CODE_KEYWORD: " CODE-ANNOTATION: "
    GUTTER_NAME: "code-annotations"
    SINGLE_LINE_WHITESPACE_REGEX_STR: "( |\\t)*"
    WHITESPACE_ONLY_REGEX: /^\s*$/
    WHITESPACE_REGEX_STR: "\\s*"

    DELETE_CONFIRM_MESSAGE: "Really delete?"
    REPLACE_CONFIRM_MESSAGE: (name) ->
        return "Asset with name '#{name}' already exists. Replace it?"
