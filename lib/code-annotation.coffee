# TODO: pass atom required object to required files (by main) in order to save require overhead
{Directory} = require 'atom'
Utils = require './utils'

CodeAnnotations = require "./constants"



module.exports = class CodeAnnotation

    # CONSTRUCTOR
    # TODO: refactor this signature...
    constructor: (codeAnnotationManager, editor, marker, gutter, assetData, assetManager) ->
        @codeAnnotationManager = codeAnnotationManager
        @editor = editor

        {@line, @name} = assetData
        @assetManager = assetManager
        @element = null
        @marker = marker

        @assetFile = null
        @renderer = null

        @_init(gutter)

    _init: (gutter) ->
        try
            @assetFile = @_getAssetFile()
            @renderer = @_getRenderer(@assetFile)

            gutterIcon = @_createGutterIcon()
            gutter.decorateMarker(@marker, {item: gutterIcon})
            @_addEventListenersToGutterIcon(gutterIcon)
        catch error
            atom.notifications.addError("Could not load code annotation '#{@name}'.", {
                detail: error.message
            })
        return @

    # PRIVATE
    _createGutterIcon: () ->
        return document.createElement("code-annotation-gutter-icon")

    _addEventListenersToGutterIcon: (gutterIcon) ->
        gutterIcon.addEventListener "click", (event) =>
            try
                @show()
            catch error
                atom.notifications.addError(error.message)
        return gutterIcon

    _createWrapper: () ->
        return document.createElement("code-annotation")

    _getAssetFile: () ->
        assets = @codeAnnotationManager.assetDirectory.getEntriesSync()
        name = @assetManager.get(@name)
        for asset in assets when asset.getBaseName() is name
            return asset
        throw new Error("Found no asset for name '#{@name}' at '#{@codeAnnotationManager.assetDirectory.getPath()}'.")

    _getRenderer: (assetFile) ->
        filename = assetFile.getBaseName()
        for rendererClass in @codeAnnotationManager.renderers
            if Utils.fileHasType(filename, rendererClass.fileExtension)
                return new rendererClass(assetFile)
        throw new Error("Found no renderer for asset '#{filename}'.")

    _updateElement: () ->
        # Utils.removeChildNodes(@element)
        # @renderer.setAsset(@assetFile)
        # @element.appendChild @renderer.render()
        @element = null
        @show()
        return @

    #######################################################################################
    # PUBLIC

    show: () ->
        if not @element?
            @_setAsset()
            @_setRenderer()
            @element = @_createWrapper()
            @element.appendChild @renderer.render()
        @codeAnnotationManager.showContainer(@, @element)
        return @

    hide: () ->
        @codeAnnotationManager.hideContainer()
        return @

    getRenderer: () ->
        return @renderer

    updateName: (newName) ->
        oldName = @name
        if oldName isnt newName
            @assetManager.updateName(oldName, newName)
                .save()
            @name = newName
            @editor.setTextInBufferRange(
                @marker.getBufferRange()
                @line.replace(oldName, newName)
            )
        return @

    edit: () ->
        console.log "editing code annotation...."
        if not @renderer
            throw new Error("Cannot edit a code annotation without a renderer. If you see this message please report a bug.")

        if @renderer.isTextBased()
            # load asset contents into new tab
            atom.workspace.open(@assetFile.getPath())
        else
            paths = Utils.chooseFile()
            if not paths?
                atom.notifications.addInfo("No new asset chosen.")
                return @
            sourcePath = paths[0]
            if not Utils.fileHasType(sourcePath, @renderer.getFileExtension())
                atom.notifications.addError("Chosen asset '#{sourcePath}' is not supported by #{@renderer.constructor.name}.")
                return @
            console.log "updating asset to #{sourcePath}..."
            destPath = @assetFile.getPath()
            sourceParts = sourcePath.split(".")
            destParts = destinationPath.split(".")
            destParts[destParts.length - 1] = sourceParts[sourceParts.length - 1]
            sourcePath = sourceParts.join(".")
            destPath = destParts.join(".")
            Utils.copyFile(sourcePath, destPath)
            @_updateElement()
        # save changes
        return @

    delete: () ->
        # strip "CODE-ANNOTATION: " for comment so the name remains for comment semantics
        @editor.setTextInBufferRange(
            @marker.getBufferRange()
            @line.replace(CodeAnnotations.CODE_KEYWORD, " ")
        )
        # remove entry from names.cson + remove asset file from file system
        @assetManager
            .delete @name
            .save()
        # remove gutter marker + decoration
        @marker.destroy()
        return @
