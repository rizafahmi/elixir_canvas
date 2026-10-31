// Keep Hakushi's connection lifecycle, markers, hit targets and export pipeline.
// Only same-item routes need an exterior perimeter instead of its generic cubic.
export function mountSelfLoops(canvas) {
  const measureHandles = canvas.measureHandles.bind(canvas)
  canvas.measureHandles = node => {
    for (const handle of node.el.querySelectorAll('.hakushi-handle')) {
      if (!handle.dataset.handle) handle.dataset.handle = handle.dataset.side
    }
    measureHandles(node)
  }
  for (const node of canvas.nodes.values()) canvas.measureHandles(node)

  const handleOf = canvas.handleOf.bind(canvas)
  canvas.handleOf = (node, id, kind, toward) => {
    if (id !== null) return handleOf(node, id, kind, toward)
    // Existing documents use automatic (null) ends. Keep their nearest-side rule.
    const place = canvas.placeOf(node)
    let nearest = null
    let distance = Infinity
    for (const handle of node.handles) {
      if (handle.kind !== 'both' && handle.kind !== kind) continue
      const d = toward ? Math.hypot(place.x + handle.x - toward.x, place.y + handle.y - toward.y) : 0
      if (d < distance) { nearest = handle; distance = d }
    }
    return nearest
  }
  const validTargets = canvas.validTargets.bind(canvas)
  canvas.validTargets = gesture => validTargets(gesture).filter(target =>
    target.end.node !== gesture.from.node || target.end.handle !== gesture.from.handle)
  const targetAt = canvas.targetAt.bind(canvas)
  canvas.targetAt = (event, gesture) => {
    // Native targetAt also snaps anywhere inside a node to its nearest valid
    // handle. Dropping on the excluded source must not snap to another side.
    const source = gesture.fromHandle?.el.getBoundingClientRect()
    if (source && Math.hypot(event.clientX - source.x - source.width / 2, event.clientY - source.y - source.height / 2) < 12) {
      canvas.root.querySelectorAll('[data-ui-target]').forEach(el => el.removeAttribute('data-ui-target'))
      return null
    }
    return targetAt(event, gesture)
  }

  const nearestHandle = (node, point) => canvas.handleOf(node, null, 'source', point)
  const arrowEnds = gesture => {
    if (gesture?.kind !== 'shape' || gesture.tool.tool !== 'line') return null
    const node = canvas.nodeAt(gesture.start)
    if (!node || canvas.nodeAt(gesture.end)?.id !== node.id) return null
    const from = nearestHandle(node, gesture.start)
    const to = nearestHandle(node, gesture.end)
    return from && to ? {node, from, to} : null
  }
  const commitShape = canvas.commitShape.bind(canvas)
  canvas.commitShape = gesture => {
    const ends = arrowEnds(gesture)
    if (!ends) return commitShape(gesture)
    if (ends.from.id !== ends.to.id) canvas.commitConnect({
      from: {node: ends.node.id, handle: ends.from.id},
      target: {end: {node: ends.node.id, handle: ends.to.id}},
    })
    canvas.setTool(null)
  }

  const route = edge => {
    if (edge.source !== edge.target || !edge.sourceHandle || !edge.targetHandle || edge.sourceHandle === edge.targetHandle) return null
    const node = canvas.nodes.get(edge.source)
    const geometry = canvas.geometry(edge)
    if (!node || !geometry) return null
    const box = canvas.rect(node)
    const center = canvas.center(node)
    // Native handle positions include rotation; the visual box includes its
    // corners too. Convert that viewport box back into canvas coordinates.
    const visual = (node.el.querySelector('[data-hakushi-rotate]') || node.el).getBoundingClientRect()
    const x = (visual.left - canvas.bounds.left - canvas.view.x) / canvas.view.zoom
    const y = (visual.top - canvas.bounds.top - canvas.view.y) / canvas.view.zoom
    const left = Math.min(box.x, x) - 48
    const top = Math.min(box.y, y) - 48
    const right = Math.max(box.x + box.width, x + visual.width / canvas.view.zoom) + 48
    const bottom = Math.max(box.y + box.height, y + visual.height / canvas.view.zoom) + 48
    const corners = [{x: left, y: top}, {x: right, y: top}, {x: right, y: bottom}, {x: left, y: bottom}]
    const exit = point => {
      const dx = point.x - center.x, dy = point.y - center.y
      const tx = dx > 0 ? (right - center.x) / dx : dx < 0 ? (left - center.x) / dx : Infinity
      const ty = dy > 0 ? (bottom - center.y) / dy : dy < 0 ? (top - center.y) / dy : Infinity
      const scale = Math.min(tx, ty)
      return {point: {x: center.x + dx * scale, y: center.y + dy * scale}, side: tx < ty ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0)}
    }
    const from = exit(geometry.from), to = exit(geometry.to)
    const walk = direction => {
      const path = [geometry.from, from.point]
      let side = from.side
      while (side !== to.side) {
        path.push(corners[(side + (direction === 1 ? 1 : 0)) % 4])
        side = (side + direction + 4) % 4
      }
      path.push(to.point, geometry.to)
      // A rotated handle ray can meet a perimeter corner exactly.
      return path.filter((point, i) => !i || Math.hypot(point.x - path[i - 1].x, point.y - path[i - 1].y) > 0.001)
    }
    const length = path => path.slice(1).reduce((sum, point, i) => sum + Math.hypot(point.x - path[i].x, point.y - path[i].y), 0)
    const clockwise = walk(1), counterclockwise = walk(-1)
    const path = length(clockwise) <= length(counterclockwise) ? clockwise : counterclockwise
    const toward = (a, b, amount) => {
      const distance = Math.hypot(b.x - a.x, b.y - a.y)
      return {x: a.x + (b.x - a.x) * amount / distance, y: a.y + (b.y - a.y) * amount / distance}
    }
    let d = `M${path[0].x},${path[0].y}`
    for (let i = 1; i < path.length - 1; i++) {
      const radius = Math.min(16, Math.hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y) / 2, Math.hypot(path[i].x - path[i + 1].x, path[i].y - path[i + 1].y) / 2)
      if (!radius) continue
      const a = toward(path[i], path[i - 1], radius), b = toward(path[i], path[i + 1], radius)
      d += `L${a.x},${a.y}Q${path[i].x},${path[i].y} ${b.x},${b.y}`
    }
    return d + `L${geometry.to.x},${geometry.to.y}`
  }
  const drawEdges = canvas.drawEdges.bind(canvas)
  canvas.drawEdges = (...args) => {
    drawEdges(...args)
    for (const edge of canvas.edges.values()) {
      const d = route(edge)
      const view = canvas.edgeViews.get(edge.id)
      if (!d || !view) continue
      view.d = d
      view.line.setAttribute('d', d)
      view.hit.setAttribute('d', d)
      const bounds = view.line.getBBox()
      if (view.label) {
        const point = view.line.getPointAtLength(view.line.getTotalLength() / 2)
        const width = view.label.offsetWidth, height = view.label.offsetHeight
        const node = canvas.nodes.get(edge.source)
        const center = canvas.center(node)
        const visual = (node.el.querySelector('[data-hakushi-rotate]') || node.el).getBoundingClientRect()
        const left = (visual.left - canvas.bounds.left - canvas.view.x) / canvas.view.zoom
        const top = (visual.top - canvas.bounds.top - canvas.view.y) / canvas.view.zoom
        const rightSide = left + visual.width / canvas.view.zoom
        const bottomSide = top + visual.height / canvas.view.zoom
        // Keep a wide label outside the item too, not merely its midpoint.
        if (Math.abs(point.x - center.x) > Math.abs(point.y - center.y)) {
          point.x = point.x > center.x ? Math.max(point.x, rightSide + width / 2 + 12) : Math.min(point.x, left - width / 2 - 12)
        } else {
          point.y = point.y > center.y ? Math.max(point.y, bottomSide + height / 2 + 12) : Math.min(point.y, top - height / 2 - 12)
        }
        view.label.style.translate = `${point.x}px ${point.y}px`
        const right = Math.max(bounds.x + bounds.width, point.x + width / 2)
        const bottom = Math.max(bounds.y + bounds.height, point.y + height / 2)
        bounds.x = Math.min(bounds.x, point.x - width / 2)
        bounds.y = Math.min(bounds.y, point.y - height / 2)
        bounds.width = right - bounds.x
        bounds.height = bottom - bounds.y
      }
      // Native edge boxes carry 80px culling slack; exportImage removes it.
      // Retain another 12px for the stroke and arrow marker in the export.
      view.box = {x: bounds.x - 92, y: bounds.y - 92, width: bounds.width + 184, height: bounds.height + 184}
      canvas.showEdge(view, true)
    }
  }
  const drawOverlay = canvas.drawOverlay.bind(canvas)
  canvas.drawOverlay = () => {
    drawOverlay()
    const gesture = canvas.gesture
    const ends = arrowEnds(gesture)
    const pending = ends && ends.from.id !== ends.to.id ? {source: ends.node.id, target: ends.node.id, sourceHandle: ends.from.id, targetHandle: ends.to.id} :
      gesture?.kind === 'connect' && gesture.target ? {source: gesture.from.node, target: gesture.target.end.node, sourceHandle: gesture.from.handle, targetHandle: gesture.target.end.handle} :
      canvas.pending ? {source: canvas.pending.source.node, target: canvas.pending.target.node, sourceHandle: canvas.pending.source.handle, targetHandle: canvas.pending.target.handle} : null
    const d = pending && route(pending)
    if (d) {
      const preview = canvas.overlay.querySelector('.hakushi-edge-pending, .hakushi-shape-preview')
      if (preview?.tagName.toLowerCase() === 'path') preview.setAttribute('d', d)
      else if (preview) {
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
        path.setAttribute('class', 'hakushi-edge-pending')
        path.setAttribute('data-ui-valid', 'true')
        path.setAttribute('d', d)
        preview.replaceWith(path)
      }
    }
  }
  canvas.allDirty = true
  canvas.schedule()
}
