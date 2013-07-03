Scribe = require('./scribe')


class Scribe.Normalizer
  @BLOCK_TAGS: [
    'ADDRESS'
    'BLOCKQUOTE'
    'DD'
    'DIV'
    'DL'
    'H1', 'H2', 'H3', 'H4', 'H5', 'H6'
    'LI'
    'OL'
    'P'
    'PRE'
    'TABLE'
    'TBODY'
    'TD'
    'TFOOT'
    'TH'
    'THEAD'
    'TR'
    'UL'
  ]

  # Missing rule implies removal
  @TAG_RULES: {
    'A'         : {}
    'ADDRESSS'  : {rename: 'div'}
    'B'         : {}
    'BLOCKQUOTE': {rename: 'div'}
    'BR'        : {}
    'BIG'       : {rename: 'span'}
    'CENTER'    : {rename: 'span'}
    'DD'        : {rename: 'div'}
    'DEL'       : {rename: 's'}
    'DIV'       : {}
    'DL'        : {rename: 'div'}
    'EM'        : {rename: 'i'}
    'H1'        : {rename: 'div'}
    'H2'        : {rename: 'div'}
    'H3'        : {rename: 'div'}
    'H4'        : {rename: 'div'}
    'H5'        : {rename: 'div'}
    'H6'        : {rename: 'div'}
    'HR'        : {rename: 'br'}
    'I'         : {}
    'INS'       : {rename: 'span'}
    'LI'        : {rename: 'div'}
    'OL'        : {rename: 'div'}
    'P'         : {rename: 'div'}
    'PRE'       : {rename: 'div'}
    'S'         : {}
    'SMALL'     : {rename: 'span'}
    'SPAN'      : {}
    'STRIKE'    : {rename: 's'}
    'STRONG'    : {rename: 'b'}
    'TABLE'     : {rename: 'div'}
    'TBODY'     : {rename: 'div'}
    'TD'        : {rename: 'span'}
    'TFOOT'     : {rename: 'div'}
    'TH'        : {rename: 'span'}
    'THEAD'     : {rename: 'div'}
    'TR'        : {rename: 'div'}
    'U'         : {}
    'UL'        : {rename: 'div'}
  }


  @applyRules: (root) ->
    Scribe.DOM.traversePreorder(root, 0, (node, index) =>
      if node.nodeType == node.ELEMENT_NODE
        rules = Scribe.Normalizer.TAG_RULES[node.tagName]
        if rules?
          _.each(rules, (data, rule) ->
            switch rule
              when 'rename' then node = Scribe.DOM.switchTag(node, data)
              else return
          )
        else
          node = Scribe.DOM.unwrap(node)
      return node
    )

  @breakBlocks: (root) ->
    Scribe.Normalizer.groupBlocks(root)
    _.each(root.querySelectorAll('br'), (node) =>
      Scribe.Normalizer.normalizeBreak(node, root)
    )
    _.each(root.childNodes, (childNode) =>
      Scribe.Normalizer.breakLine(childNode)
    )

  @breakLine: (lineNode) ->
    return if lineNode.childNodes.length == 1 and lineNode.firstChild.tagName == 'BR'
    Scribe.DOM.traversePostorder(lineNode, (node) =>
      if Scribe.Utils.isBlock(node)
        node = Scribe.DOM.switchTag(node, 'div') if node.tagName != 'DIV'
        if node.nextSibling?
          line = lineNode.ownerDocument.createElement('div')
          lineNode.parentNode.insertBefore(line, lineNode.nextSibling)
          while node.nextSibling?
            line.appendChild(node.nextSibling)
          Scribe.Normalizer.breakLine(line)
        return Scribe.DOM.unwrap(node)
      else
        return node
    )

  @groupBlocks: (root) ->
    curLine = root.firstChild
    while curLine?
      if Scribe.Utils.isBlock(curLine)
        curLine = curLine.nextSibling
      else
        line = root.ownerDocument.createElement('div')
        root.insertBefore(line, curLine)
        while curLine? and !Scribe.Utils.isBlock(curLine)
          nextLine = curLine.nextSibling
          line.appendChild(curLine)
          curLine = nextLine
        curLine = line

  @normalizeBreak: (node, root) ->
    return if node == root
    if node.previousSibling?
      if node.nextSibling?
        Scribe.DOM.splitAfter(node, root)
      node.parentNode.removeChild(node)
    else if node.nextSibling?
      if Scribe.DOM.splitAfter(node, root)
        Scribe.Normalizer.normalizeBreak(node, root)
    else if node.parentNode != root and node.parentNode.parentNode != root
      # Make sure <div><br/></div> is not unintentionally unwrapped
      Scribe.DOM.unwrap(node.parentNode)
      Scribe.Normalizer.normalizeBreak(node, root)

  @normalizeHtml: (html) ->
    # Remove leading and tailing whitespace
    html = html.replace(/^\s\s*/, '').replace(/\s\s*$/, '')
    # Remove whitespace between tags
    html = html.replace(/\>\s+\</g, '><')
    # Standardize br
    html = html.replace(/<br><\/br>/, '<br>')
    return html

  @removeNoBreak: (root) ->
    Scribe.DOM.traversePreorder(root, 0, (node) =>
      if node.nodeType == node.TEXT_NODE
        node.textContent = node.textContent.split(Scribe.DOM.NOBREAK_SPACE).join('')
      return node
    )

  @requireLeaf: (lineNode) ->
    unless lineNode.childNodes.length > 1
      if lineNode.tagName == 'OL' || lineNode.tagName == 'UL'
        lineNode.appendChild(lineNode.ownerDocument.createElement('li'))
        lineNode = lineNode.firstChild
      lineNode.appendChild(lineNode.ownerDocument.createElement('br'))
    
  @wrapText: (lineNode) ->
    Scribe.DOM.traversePreorder(lineNode, 0, (node) =>
      Scribe.DOM.normalize(node)
      if node.nodeType == node.TEXT_NODE && (node.nextSibling? || node.previousSibling? || node.parentNode == lineNode or node.parentNode.tagName == 'LI')
        span = node.ownerDocument.createElement('span')
        Scribe.DOM.wrap(span, node)
        node = span
      return node
    )


  constructor: (@container, @formatManager) ->

  mergeAdjacent: (lineNode) ->
    Scribe.DOM.traversePreorder(lineNode, 0, (node) =>
      if node.nodeType == node.ELEMENT_NODE and !Scribe.Line.isLineNode(node)
        next = node.nextSibling
        if next?.tagName == node.tagName and node.tagName != 'LI'
          [nodeFormat, nodeValue] = @formatManager.getFormat(node)
          [nextFormat, nextValue] = @formatManager.getFormat(next)
          if nodeFormat == nextFormat && nodeValue == nextValue
            node = Scribe.DOM.mergeNodes(node, next)
      return node
    )

  normalizeDoc: ->
    @container.appendChild(@container.ownerDocument.createElement('div')) unless @container.firstChild
    Scribe.Normalizer.applyRules(@container)
    Scribe.Normalizer.breakBlocks(@container)
    _.each(@container.childNodes, (lineNode) =>
      this.normalizeLine(lineNode)
      this.optimizeLine(lineNode)
    )

  normalizeLine: (lineNode) ->
    return if lineNode.childNodes.length == 1 and lineNode.childNodes[0].tagName == 'BR'
    Scribe.Normalizer.removeNoBreak(lineNode)
    this.normalizeTags(lineNode)
    Scribe.Normalizer.requireLeaf(lineNode)
    Scribe.Normalizer.wrapText(lineNode)

  normalizeTags: (lineNode) ->
    Scribe.DOM.traversePreorder(lineNode, 0, (node) =>
      [nodeFormat, nodeValue] = @formatManager.getFormat(node)
      if @formatManager.formats[nodeFormat]?
        @formatManager.formats[nodeFormat].clean(node)
      else
        Scribe.DOM.removeAttributes(node)
    )

  optimizeLine: (lineNode) ->
    return if lineNode.childNodes.length == 1 and lineNode.childNodes[0].tagName == 'BR'
    this.mergeAdjacent(lineNode)
    this.removeRedundant(lineNode)
    Scribe.Normalizer.wrapText(lineNode)

  removeRedundant: (lineNode) ->
    key = _.uniqueId('_Formats')
    lineNode[key] = {}
    isRedudant = (node) =>
      if node.nodeType == node.ELEMENT_NODE
        if Scribe.Utils.getNodeLength(node) == 0
          return node.tagName != 'BR' or node.parentNode.childNodes.length > 1
        [formatName, formatValue] = @formatManager.getFormat(node)
        if formatName?
          return node.parentNode[key][formatName]?     # Parent format value will overwrite child's so no need to check formatValue
        else if node.tagName == 'SPAN'
          # Check if childNodes need us
          if node.childNodes.length == 0 or !_.any(node.childNodes, (child) -> child.nodeType != child.ELEMENT_NODE)
            return true
          # Check if parent needs us
          if node.previousSibling == null && node.nextSibling == null and node.parentNode != lineNode and node.parentNode.tagName != 'LI'
            return true
      return false
    Scribe.DOM.traversePreorder(lineNode, 0, (node) =>
      if isRedudant(node)
        node = Scribe.DOM.unwrap(node)
      if node?
        node[key] = _.clone(node.parentNode[key])
        [formatName, formatValue] = @formatManager.getFormat(node)
        node[key][formatName] = formatValue if formatName?
      return node
    )
    delete lineNode[key]
    Scribe.DOM.traversePreorder(lineNode, 0, (node) ->
      delete node[key]
      return node
    )


module.exports = Scribe
