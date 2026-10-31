// Hakushi rotates the rendered shape, but mounts selection controls on its
// unrotated authored box. Keep those native controls in the same local frame.
export function mountRotationGuides(canvas) {
  const rotationElement = node => node.type === "shape" && node.el.querySelector("[data-hakushi-rotate]")
  const rotationOf = element => parseFloat(getComputedStyle(element).getPropertyValue("--hakushi-rotation")) || 0
  const setStyle = (element, property, value) => {
    if (element.style.getPropertyValue(property) !== value) element.style.setProperty(property, value)
  }
  const syncGuides = node => {
    const element = rotationElement(node)
    const active = element && canvas.selected.size === 1 && canvas.selected.has(node.id)
    const wasActive = node.el.classList.contains("drawing-rotation-guides")
    if (!active && !wasActive) return
    node.el.classList.toggle("drawing-rotation-guides", Boolean(active))
    const angle = active ? rotationOf(element) : 0
    if (active) setStyle(node.el, "--drawing-guide-angle", `${angle}deg`)
    else node.el.style.removeProperty("--drawing-guide-angle")
    for (const control of node.el.querySelectorAll(":scope > .hakushi-resizer, :scope > .hakushi-rotator")) {
      if (!active) {
        control.style.removeProperty("transform-origin")
        control.style.removeProperty("cursor")
        continue
      }
      const corner = control.dataset.corner
      if (!corner) {
        setStyle(control, "transform-origin", `6px ${node.height / 2 + 28}px`)
        continue
      }
      const x = 5 + (corner.includes("w") ? node.width / 2 : corner.includes("e") ? -node.width / 2 : 0)
      const y = 5 + (corner.includes("n") ? node.height / 2 : corner.includes("s") ? -node.height / 2 : 0)
      setStyle(control, "transform-origin", `${x}px ${y}px`)
      const direction = corner.length === 2 ? (corner === "nw" || corner === "se" ? 45 : 135) : (corner === "n" || corner === "s" ? 90 : 0)
      const axis = (Math.round((angle + direction) / 45) % 4 + 4) % 4
      setStyle(control, "cursor", ["ew-resize", "nwse-resize", "ns-resize", "nesw-resize"][axis])
    }
  }

  const decorate = canvas.decorate.bind(canvas)
  canvas.decorate = node => {
    const resize = canvas.gesture?.kind === "resize" && canvas.gesture.id === node.id && canvas.gesture.guideResize
    if (resize) {
      // Native sizing retains its min/snap/aspect rules. Recenter that local
      // box so its opposite rotated corner (or side midpoint) stays fixed.
      const x = (resize.anchorX - 0.5) * node.width
      const y = (resize.anchorY - 0.5) * node.height
      node.x = Math.round((resize.anchor.x - x * resize.cos + y * resize.sin - node.width / 2) * 100) / 100
      node.y = Math.round((resize.anchor.y - x * resize.sin - y * resize.cos - node.height / 2) * 100) / 100
    }
    decorate(node)
    syncGuides(node)
  }
  const measureHandles = canvas.measureHandles.bind(canvas)
  canvas.measureHandles = node => {
    measureHandles(node)
    syncGuides(node)
  }
  const refresh = id => {
    const node = canvas.nodes.get(id)
    if (!node) return
    canvas.measureHandles(node)
    canvas.touchNode(id)
    canvas.schedule()
  }

  const startRotate = canvas.startRotate.bind(canvas)
  canvas.startRotate = (event, node) => {
    startRotate(event, node)
    const gesture = canvas.gesture
    if (gesture?.kind === "rotate" && rotationElement(node)) {
      canvas.root.focus({preventScroll: true})
      // Removing the native preview property also removes Shapes' saved inline
      // rotation. Keep the exact base declaration for cancel and no-op drags.
      gesture.guideRotation = gesture.el.style.getPropertyValue("--hakushi-rotation")
    }
  }
  const pointerDown = canvas.pointerDown.bind(canvas)
  canvas.pointerDown = event => {
    if ((canvas.gesture?.guideResize || canvas.gesture?.guideRotation !== undefined) && !canvas.pointers.has(event.pointerId)) {
      // Cancel releases the preview's capture; native pinch still needs both
      // touches, including the first one that cancel removes from its map.
      const pointers = new Map(canvas.pointers)
      canvas.cancelGesture()
      canvas.pointers = pointers
    }
    pointerDown(event)
    const gesture = canvas.gesture
    if (gesture?.kind !== "resize" || gesture.pointer !== event.pointerId || canvas.selected.size !== 1 || !canvas.selected.has(gesture.id)) return
    const node = canvas.nodes.get(gesture.id)
    const element = node && rotationElement(node)
    const angle = element && rotationOf(element)
    if (!angle) return
    canvas.root.focus({preventScroll: true})
    const theta = angle * Math.PI / 180
    const cos = Math.cos(theta), sin = Math.sin(theta)
    const anchorX = gesture.corner.includes("e") ? 0 : gesture.corner.includes("w") ? 1 : 0.5
    const anchorY = gesture.corner.includes("s") ? 0 : gesture.corner.includes("n") ? 1 : 0.5
    const x = (anchorX - 0.5) * gesture.rect.width
    const y = (anchorY - 0.5) * gesture.rect.height
    gesture.guideResize = {cos, sin, anchorX, anchorY, anchor: {
      x: gesture.rect.x + gesture.rect.width / 2 + x * cos - y * sin,
      y: gesture.rect.y + gesture.rect.height / 2 + x * sin + y * cos,
    }}
  }

  const canvasPoint = canvas.canvasPoint.bind(canvas)
  canvas.canvasPoint = event => {
    const point = canvasPoint(event)
    const gesture = canvas.gesture
    const resize = gesture?.kind === "resize" && gesture.pointer === event.pointerId && gesture.guideResize
    if (!resize) return point
    const x = point.x - gesture.start.x, y = point.y - gesture.start.y
    return {x: gesture.start.x + x * resize.cos + y * resize.sin,
      y: gesture.start.y - x * resize.sin + y * resize.cos}
  }
  const pointerMove = canvas.pointerMove.bind(canvas)
  canvas.pointerMove = event => {
    pointerMove(event)
    const gesture = canvas.gesture
    if (gesture?.pointer !== event.pointerId) return
    if (gesture.kind === "rotate" && gesture.guideRotation !== undefined) refresh(gesture.id)
    // Native resize consumes the mapped point; peer/hover pointers stay in world space.
    if (gesture.kind === "resize" && gesture.guideResize) canvas.pointer = canvasPoint(event)
  }

  const restoreRotation = gesture => {
    if (gesture.guideRotation) gesture.el.style.setProperty("--hakushi-rotation", gesture.guideRotation)
    else gesture.el.style.removeProperty("--hakushi-rotation")
  }
  const release = gesture => {
    canvas.pointers.delete(gesture.pointer)
    if (canvas.root.hasPointerCapture(gesture.pointer)) canvas.root.releasePointerCapture(gesture.pointer)
  }
  const pointerUp = canvas.pointerUp.bind(canvas)
  canvas.pointerUp = (event, cancelled = false) => {
    const gesture = canvas.gesture
    pointerUp(event, cancelled)
    if (gesture?.pointer !== event.pointerId) return
    if (gesture.kind === "rotate" && gesture.guideRotation !== undefined) {
      if (cancelled || gesture.deg === gesture.base) restoreRotation(gesture)
      refresh(gesture.id)
    }
    if (gesture.kind === "resize" && gesture.guideResize && cancelled) {
      const node = canvas.nodes.get(gesture.id)
      if (node) canvas.readNode(node.el)
      refresh(gesture.id)
    }
  }
  const cancelGesture = canvas.cancelGesture.bind(canvas)
  canvas.cancelGesture = () => {
    const gesture = canvas.gesture
    cancelGesture()
    if (gesture?.kind === "rotate" && gesture.guideRotation !== undefined) {
      restoreRotation(gesture)
      release(gesture)
      refresh(gesture.id)
    }
    if (gesture?.kind === "resize" && gesture.guideResize) {
      release(gesture)
      refresh(gesture.id)
    }
  }
  const lostCapture = event => {
    const gesture = canvas.gesture
    if (gesture?.pointer === event.pointerId && (gesture.guideResize || gesture.guideRotation !== undefined)) canvas.cancelGesture()
  }
  canvas.root.addEventListener("lostpointercapture", lostCapture)
  for (const node of canvas.nodes.values()) syncGuides(node)
  return () => canvas.root.removeEventListener("lostpointercapture", lostCapture)
}
