{CompositeDisposable, Directory, Range, TextEditor} = require "atom"
CSON = require "season"
libpath = require "path"
# fs = require "fs-plus"
# $ = jQuery = require "jquery"
# {$, jQuery, TextEditorView, View} = require "atom-space-pen-views"

CodeAnnotations = require "./constants"
settings = require "./settings"
Utils = require "./utils"

AssetManager = require "./asset-manager"
CodeAnnotation = require "./code-annotation"
CodeAnnotationContainer = require "./code-annotation-container"
{AssetRenderer, HtmlRenderer, ImageRenderer, TextRenderer} = require "./asset-renderers/all-renderers"
Dialog = require "./dialog.coffee"
CodeAnnotationNameDialog = require "./asset-name-dialog.coffee"



###
@class CodeAnnotationManager
Has a CodeAnnotationContainer which contains the output of an asset renderer.
###
module.exports = CodeAnnotationManager =
    # this is my awesome annotation
    config: settings

    # instance properties
    subscriptions: null
    renderers: []
    codeAnnotations: []
    currentCodeAnnotation: null
    annotationRegexCache: {}
    assetNames: {}
    assetManagers: {}
    assetDirectories: []
    assetDirectory: null
    initializedEditors: {}

    #######################################################################################
    # PUBLIC (ATOM API)

    activate: (state) ->
        @subscriptions = new CompositeDisposable()
        @_init()

    deactivate: () ->
        @subscriptions.dispose()
        @_destroyEditors()
        return @

    serialize: () ->
        return {}

    #######################################################################################
    # PUBLIC

    # API method for plugin packages to register their own renderers for file types
    registerRenderer: (rendererClass) ->
        if rendererClass in @renderers
            throw new Error("The AssetRenderer is already defined to file type '#{rendererClass.fileExtension}'.")
        if not rendererClass.isSubclassOf AssetRenderer
            throw new Error("Invalid asset renderer. Expected a subclass of AssetRenderer.")
        @renderers.push rendererClass
        return @

    addCodeAnnotationAtLine: (point) ->
        dialog = new CodeAnnotationNameDialog()
        dialog.attach().onSubmit (name) =>
            editor = atom.workspace.getActiveTextEditor()
            assetManager = @assetManagers[@_getAssetDirectoryForEditor(editor).getPath()]
            if assetManager.has(name) and not confirm("Asset with name '#{name}' already exists. Replace it?")
                return @
            @_createNewCodeAnnotation(editor, point, name, assetManager)
            return @
        return @

    deleteCodeAnnotationAtLine: (point) ->
        # TODO: check if annotation actually exists for the line (show notification otherwise)
        if not confirm("Really delete?")
            return @

        editor = atom.workspace.getActiveTextEditor()
        assetManager = @assetManagers[@_getAssetDirectoryForEditor(editor).getPath()]
        # @_removeCodeAnnotation(editor, point, @_getCodeAnnotationAtPoint(editor, point))
        # del test
        try
            @_getCodeAnnotationAtPoint(editor, point).delete()
        catch error
            throw new Error("code-annotations: Could not find a code annotation at the current cursor.")
        return @

    # addCodeAnnotation: () ->
    #     line = null
    #     @addCodeAnnotationAtLine(line)
    #     return @
    #
    # deleteCodeAnnotation: () ->
    #     line = null
    #     @deleteCodeAnnotationAtLine(line)
    #     return @

    # CODE-ANNOTATION: image-testasset
    # CODE-ANNOTATION: html-testasset
    # CODE-ANNOTATION: text-testasset

    showContainer: (editor, renderedContent) ->
        {container} = @initializedEditors[editor.getPath()]
        if container?
            container.empty()
                .append(renderedContent)
                .show()
            return @
        throw new Error("No container found")

    hideContainer: (editor) ->
        {container} = @initializedEditors[editor.getPath()]
        if container?
            container.hide()
            return @
        throw new Error("No container found")

    setCurrentCodeAnnotation: (codeAnnotation) ->
        @currentCodeAnnotation = codeAnnotation
        return @

    getCurrentCodeAnnotation: () ->
        return @currentCodeAnnotation

    # get current renderer (associated with the CodeAnnotationContainer)
    getRenderer: () ->
        return @currentCodeAnnotation.getRenderer()

    showAll: () ->
        # TODO: create search window like cmd+shift+p
        return @

    #######################################################################################
    # PRIVATE

    _init: () ->
        for dir in atom.project.getDirectories()
            subdir = dir.getSubdirectory(CodeAnnotations.ASSET_DIR_NAME)
            if subdir.existsSync()
                @assetDirectories.push subdir
        # @assetDirectory = atom.project.getDirectories()[0].getSubdirectory(".code-annotations")
        @assetDirectory = @assetDirectories[0]
        console.log @assetDirectories

        @_registerCommands()
        @_registerElements()
        @_loadAssetManagers()

        # add default renderers
        @registerRenderer(ImageRenderer)
        @registerRenderer(HtmlRenderer)
        @registerRenderer(TextRenderer)

        atom.workspace.observeActivePaneItem (editor) =>
            if editor instanceof TextEditor
                # console.log 'observeActivePaneItem: ', editor
                path = editor.getPath()
                if not @initializedEditors[path]? or @initializedEditors[path].editor isnt editor
                    try
                        @_initEditor editor
                    catch error
                        throw new Error("code-annotations: Error while initializing the editor with path '#{editor.getPath()}'.")
            return @

    # this method loads all the data necessary for displaying code annotations and displays the gutter icons for a certain TextEditor
    _initEditor: (editor) ->
        grammar = editor.getGrammar()
        try
            regex = @_getAnnotationRegex(grammar)
            console.log regex
        # comments not supported => do not modify editor
        # TODO: keep list of unsupported editors so this method does not get called when switching to previously done but unsupported editors
        catch error
            console.log "unsupported grammer (no comments available => thus no annotations)"
            return @

        console.log "initializing editor w/ path: #{editor.getPath()}"
        gutter = editor.addGutter({
            name: "code-annotations"
            priority: CodeAnnotations.GUTTER_PRIO
            visible: true
        })

        container = new CodeAnnotationContainer(@)
        editorView = atom.views.getView(editor)
        editorView.shadowRoot.appendChild container.getElement()

        ranges = []
        assetData = []

        editor.scan regex, ({match, matchText, range}) ->
            # matchText = matchText.trim()
            # console.log match, matchText, range.toString()
            assetData.push {
                line: matchText
                name: matchText.slice(matchText.indexOf(CodeAnnotations.CODE_KEYWORD) + CodeAnnotations.CODE_KEYWORD.length).trim()
            }
            ranges.push range
            return true

        assetDirectoryPath = @_getAssetDirectoryForEditor(editor)
        codeAnnotations = []
        for range, i in ranges
            marker = editor.markBufferRange(range)
            codeAnnotation = new CodeAnnotation(
                @
                editor
                marker
                gutter
                assetData[i]
                @assetManagers[assetDirectoryPath.getPath()]
            )
            # console.log "assetDirectoryPath", assetDirectoryPath, @assetManagers
            codeAnnotations.push codeAnnotation

        # TODO: there is not necessarily only 1 editor for 1 path. (e.g. split panes). so for each path there should be a list of unique editors (like a hashmap with editor.getPath() as the hash of the editor)
        # TODO: add editor:path‐changed hook to reinitialize
        @initializedEditors[editor.getPath()] =
            assetDirectory: assetDirectoryPath
            assetManager: @assetManagers[assetDirectoryPath]
            codeAnnotations: codeAnnotations
            container: container
            editor: editor
            gutter: gutter
        return @

    # # this method is called when the code-annotations gutter changes (i.e. after adding/removing code annotations)
    # # so it's like _initEditor() but with creating a gutter and stuff...
    # _updateEditor: (editor) ->
    #     for codeAnnotation in @initializedEditors[editor.getPath()].codeAnnotations
    #         codeAnnotation.--delete()
    #
    #     ranges = []
    #     assetData = []
    #
    #     editor.scan regex, ({match, matchText, range}) ->
    #         # matchText = matchText.trim()
    #         # console.log match, matchText, range.toString()
    #         assetData.push {
    #             line: matchText
    #             name: matchText.slice(matchText.indexOf(CodeAnnotations.CODE_KEYWORD) + CodeAnnotations.CODE_KEYWORD.length).trim()
    #         }
    #         ranges.push range
    #         return true
    #
    #     assetDirectoryPath = @_getAssetDirectoryForEditor(editor)
    #     codeAnnotations = []
    #     for range, i in ranges
    #         marker = editor.markBufferRange(range)
    #         icon = @_createGutterIcon()
    #         decoration = gutter.decorateMarker(marker, {
    #             item: icon
    #         })
    #         codeAnnotation = new CodeAnnotation(
    #             @
    #             editor
    #             marker
    #             decoration
    #             icon
    #             assetData[i]
    #             @assetManagers[assetDirectoryPath.getPath()]
    #         )
    #         # console.log "assetDirectoryPath", assetDirectoryPath, @assetManagers
    #         codeAnnotations.push codeAnnotation
    #
    #     # TODO: there is not necessarily only 1 editor for 1 path. (e.g. split panes). so for each path there should be a list of unique editors (like a hashmap with editor.getPath() as the hash of the editor)
    #     # TODO: add editor:path‐changed hook to reinitialize
    #     @initializedEditors[editor.getPath()] =
    #         assetDirectory: assetDirectoryPath
    #         assetManager: @assetManagers[assetDirectoryPath]
    #         codeAnnotations: codeAnnotations
    #         container: container
    #         editor: editor
    #         gutter: gutter
    #     return @

    # get the name of the codeAnnotation at the given point
    _getCodeAnnotationAtPoint: (editor, point) ->
        editorPath = editor.getPath()
        editorData = @initializedEditors[editorPath]

        for codeAnnotation in editorData.codeAnnotations when codeAnnotation.marker.getBufferRange().start.row is point.row
            return codeAnnotation
        return null

    # takes care of removing the unnecessary stuff (i.e. dom nodes)
    # i guess all refs to this singleton are also disposed so everything else will be cleared from memory as well
    _destroyEditors: () ->
        for editorData in @initializedEditors
            editorData.editor.getGutterWithName("code-annotations").destroy()
            editorData.container.destroy()
        return @

    _loadAssetManagers: () ->
        for assetDirectory in @assetDirectories
            path = assetDirectory.getPath()
            @assetManagers[path] = new AssetManager(path)
        console.log "assetManagers", @assetManagers
        return @

    _getAssetDirectoryForEditor: (editor) ->
        editorPath = editor.getPath()
        # return from "cache"
        if @initializedEditors[editorPath]?.assetDirectory?
            return @initializedEditors[editorPath].assetDirectory
        # actually find the dir
        for assetDirectory in @assetDirectories
            projectRoot = assetDirectory.getParent()
            if projectRoot.contains(editorPath)
                return assetDirectory
        throw new Error("Cannot add a code annotation to files outside of the current projects.")

    _getEditorData: (editor) ->
        return @initializedEditors[editor.getPath()]
        # dataList = @initializedEditors[editor.getPath()]
        # if dataList?
        #     for data in dataList when data.editor is editor
        #         return data
        # return {}

    _registerCommands: () ->
        @subscriptions.add atom.commands.add 'atom-workspace', {
            # 'code-annotations:add-code-annotation': () =>
            #     return @addCodeAnnotation()
            # 'code-annotations:delete-code-annotation': () =>
            #     return @deleteCodeAnnotation()
            'code-annotations:add-code-annotation-at-line': () =>
                # TODO: retrieve current line and pass it to addCodeAnnotationAtLine()
                return @addCodeAnnotationAtLine(atom.workspace.getActiveTextEditor().getCursorBufferPosition())
            'code-annotations:delete-code-annotation-at-line': () =>
                # TODO: retrieve current line and pass it to deleteCodeAnnotation()
                # line = null
                # return @deleteCodeAnnotation(line)
                return @deleteCodeAnnotationAtLine(atom.workspace.getActiveTextEditor().getCursorBufferPosition())
            'code-annotations:hide-container': () =>
                return @hideContainer()
            'code-annotations:show-all': () =>
                return @showAll()
        }
        return @

    _registerElements: () ->
        document.registerElement("code-annotation-gutter-icon", {
            prototype: Object.create(HTMLDivElement.prototype)
            extends: "div"
        })
        document.registerElement("code-annotation", {
            prototype: Object.create(HTMLDivElement.prototype)
            extends: "div"
        })
        return @

    ###
    # Creates an entirely new code annotation.
    # Therefore, an asset is copied and the .names.cson is updated.
    # @param Object assetManager Equals this.assetManagers[current editor's asset path].
    ###
    _createNewCodeAnnotation: (editor, point, name, assetManager) ->
        # TODO: enable entering a content and an asset type (i.e. html content without having to create a file 1st)
        paths = Utils.chooseFile("Now, choose an asset.")
        if not paths?
            atom.notifications.addError("No asset chosen.")
            return @
        assetPath = paths[0]
        console.log name, assetPath

        # update asset name "database" (this should not throw errors because the manager should never be null, name collisions were checked before and the manager should never have been initialized with a wrong path (so save should work))
        assetManager
            .set name, assetPath
            .save()

        indentation = editor.indentationForBufferRow(point.row)
        range = [[point.row, 0], [point.row, 0]]
        line = "#{CodeAnnotations.CODE_KEYWORD.trim()} #{name}\n"
        editor.setTextInBufferRange(range, line)
        # make it a comment
        editor.setSelectedBufferRange(range)
        editor.toggleLineCommentsInSelection()
        # editor.toggleLineCommentForBufferRow(point.row)
        # make sure it's indented correctly
        editor.setIndentationForBufferRow(point.row, indentation)
        editor.setCursorBufferPosition([point.row, line.length - 1])

        editorData = @_getEditorData(editor)

        marker = editor.markBufferRange(range)
        codeAnnotation = new CodeAnnotation(
            @
            editor
            marker
            editorData.gutter
            {name, line}
            assetManager
        )
        editorData.codeAnnotations.push codeAnnotation
        return @

    _getAnnotationRegex: (grammar) ->
        if @annotationRegexCache[grammar.name]?
            return @annotationRegexCache[grammar.name]

        patternData = null
        for pattern in grammar.rawPatterns
            {name, begin, end} = pattern
            if name? and begin? and end?
                if pattern.name.indexOf("comment") >= 0 and pattern.name.indexOf("line") >= 0
                    # TODO: maybe this last line is annotated. in that case a trailing newline (e.g. coffeescript's pattern.end) should not be part of the regex (or optional) so the last line will be matched
                    @annotationRegexCache[grammar.name] =  new RegExp(
                        CodeAnnotations.SINGLE_LINE_WHITESPACE_REGEX_STR +
                        pattern.begin +
                        CodeAnnotations.CODE_KEYWORD +
                        ".*?" +
                        pattern.end,
                        "g"
                    )
                    return @annotationRegexCache[grammar.name]
        # ...some grammars don't have comments (e.g. JSON)
        throw new Error("Could not find a regular expression for grammar '#{grammar.name}'.")
