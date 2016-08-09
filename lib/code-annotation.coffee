# TODO: pass atom required object to required files (by main) in order to save require overhead
path = require "path"

{Directory} = require 'atom'
Utils = require './utils'
CodeAnnotations = require "./constants"



module.exports = class CodeAnnotation

    constructor: (codeAnnotationManager, editorData, assetData, fallbackRenderer) ->
        @codeAnnotationManager = codeAnnotationManager

        {@editor, @marker, gutter} = editorData

        {@assetManager, @line, @name} = assetData
        @element = null

        @assetFile = null
        @renderer = null
        @fallbackRenderer = fallbackRenderer or null

        @_init(gutter)

    _init: (gutter) ->
        @assetFile = @_getAssetFile()
        @renderer = @_getRenderer(@assetFile, @fallbackRenderer)

        gutterIcon = @_createGutterIcon()
        gutter.decorateMarker(@marker, {item: gutterIcon})
        @_addEventListenersToGutterIcon(gutterIcon)
        # try
        #     @assetFile = @_getAssetFile()
        #     @renderer = @_getRenderer(@assetFile)
        #
        #     gutterIcon = @_createGutterIcon()
        #     gutter.decorateMarker(@marker, {item: gutterIcon})
        #     @_addEventListenersToGutterIcon(gutterIcon)
        # catch error
        #     atom.notifications.addError("Could not load code annotation '#{@name}'.", {
        #         detail: error.message
        #     })
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

    _getRenderer: (assetFile, fallbackRenderer) ->
        filename = assetFile.getBaseName()
        renderer = fallbackRenderer
        # TODO: instead of length take the number of dots!
        maxLength = -1
        for rendererClass in @codeAnnotationManager.renderers
            # if Utils.fileHasType(filename, rendererClass.fileExtension)
                # return new rendererClass(assetFile)
            {result, length} = rendererClass.supports(filename)
            if result is true and length > maxLength
                renderer = rendererClass
                maxLength = length
        if renderer?
            return new renderer(assetFile)
        throw new Error("Found no renderer for asset '#{filename}' of code annotation '#{@name}'.")

    _updateElement: () ->
        @element = null
        @show()
        return @

    #######################################################################################
    # PUBLIC

    show: () ->
        if not @element?
            @element = @_createWrapper()
            @element.appendChild @renderer.render(@codeAnnotationManager)
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
        # load asset contents into a TextEditor
        if @renderer.isTextBased()
            atom.workspace.open(@assetFile.getPath())
        # choose new file as asset
        else
            paths = Utils.chooseFile()
            if not paths?
                # atom.notifications.addInfo("No new asset chosen.")
                return @

            newAssetPath = paths[0]
            # remove old file if it's of a new type
            if path.extname(newAssetPath).toLowerCase() isnt path.extname(@assetFile.getBaseName())
                @assetManager.delete(@name)

            @assetManager.set(@name, newAssetPath)
                .save()

            @assetFile = @_getAssetFile()
            @renderer = @_getRenderer(@assetFile, @fallbackRenderer)
            @_updateElement()
        return @

    changeType: (rendererClass) ->
        assetName = @assetFile.getBaseName()
        assetName = assetName.replace(path.extname(assetName), ".#{rendererClass.getFileExtension()}")
        @assetManager.renameAsset(@name, assetName)
            .save()
        @assetFile = @codeAnnotationManager.assetDirectory.getFile(assetName)
        @renderer = new rendererClass(@assetFile)
        @_updateElement()
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
