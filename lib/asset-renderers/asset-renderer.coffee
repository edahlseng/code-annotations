Utils = require '../utils'

module.exports = class AssetRenderer

    @parent: null
    # string or array of strings. must be lower case. must not begin with a dot
    @fileExtension: null
    # asset kind: text-based -> directly editable, not text-based (= binary) -> replaceable only
    @isTextBased: null

    # CONSTRUCTOR
    constructor: (asset) ->
        @asset = asset

    @isSubclassOf: (clss) ->
        if clss is @
            return false
        c = @
        while c.parent?
            c = c.parent
            if c is clss
                return true
        return false

    @supports: (filename) ->
        if typeof @fileExtension is "string"
            fileExtensions = [@fileExtension]
        else
            fileExtensions = @fileExtension
        for fileExtension in fileExtensions when filename.slice(-fileExtension.length - 1).toLowerCase() is ".#{fileExtension}"
            return {
                length: fileExtension.length
                result: true
            }
        return {
            length: 0
            result: false
        }

    render: () ->
        element = @_render()
        element.className = "#{element.className} rendered #{Utils.camelToKebab(@constructor.name)}"
        return element

    _render: () ->
        throw new Error("_render() method must be implemented by '#{@constructor.name}'.")

    isTextBased: () ->
        return @constructor.isTextBased

    getFileExtension: () ->
        return @constructor.fileExtension

    setAsset: (asset) ->
        @asset = asset
        return @
