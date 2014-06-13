# ### Patches
  
# Class Patches is a singleton 2D matrix of Patch instances, each patch 
# representing a 1x1 square in patch coordinates (via 2D coord transforms).
#
# From ABM.world, set in Model:
#
# * size:         pixel h/w of each patch.
# * minX/maxX:    min/max x coord in patch coords
# * minY/maxY:    min/max y coord in patch coords
# * numX/numY:    width/height of grid.
# * isTorus:      true if coord system wraps around at edges
# * isHeadless:   true if not using canvas drawing

class ABM.Patches extends ABM.Set
  # Constructor: super creates the empty Set instance and installs
  # the agentClass (breed) variable shared by all the Patches in this set.
  # Patches are created from top-left to bottom-right to match data sets.
  constructor: -> # agentClass, name, mainSet
    super # call super with all the args I was called with
    @monochrome = false # set to true to optimize patches all default color
    @[key] = value for own key, value of ABM.world # add world items to patches
  
  # Setup patch world from world parameters.
  # Note that this is done as separate method so like other agentsets,
  # patches are started up empty and filled by "create" calls.
  create: -> # TopLeft to BottomRight, exactly as canvas imagedata
    for y in [@maxY..@minY] by -1
      for x in [@minX..@maxX] by 1
        @add new @agentClass x, y
    @setPixels() unless @isHeadless # setup off-page canvas for pixel ops
    @
    
  # Have patches cache the agents currently on them.
  # Optimizes p.agentsHere method.
  # Call before first agent is created.
  cacheAgentsHere: ->
    for patch in @
      patch.agents = []
    null

  # Draw patches using scaled image of colors. Note anti-aliasing may occur
  # if browser does not support smoothing flags.
  usePixels: (@drawWithPixels = true) ->
    context = ABM.contexts.patches
    u.setContextSmoothing context, not @drawWithPixels

  # Optimization: Cache a single set by modeler for use by
  # patchRectangle, inCone, inRectangle, inRadius.
  # Ex: flock demo model's vision rect.
  cacheRectangle: (radius, meToo = false) ->
    for patch in @
      patch.pRectangle = @patchRectangle patch, radius, radius, meToo
      patch.pRectangle.radius = radius #; patch.pRectangle.meToo = meToo
    radius

  # Setup pixels used for `drawScaledPixels` and `importColors`
  # 
  setPixels: ->
    if @size is 1
      @usePixels()
      @pixelsContext = ABM.contexts.patches
    else
      @pixelsContext = u.createContext @numX, @numY

    @pixelsImageData = @pixelsContext.getImageData(0, 0, @numX, @numY)
    @pixelsData = @pixelsImageData.data

    if @pixelsData instanceof Uint8Array # Check for typed arrays
      @pixelsData32 = new Uint32Array @pixelsData.buffer
      @pixelsAreLittleEndian = u.isLittleEndian()
  
  # Draw patches.  Three cases:
  #
  # * Pixels: use pixel manipulation rather than canvas draws
  # * Monochrome: just fill canvas w/ patch default
  # * Otherwise: just draw each patch individually
  draw: (context) ->
    if @monochrome
      u.fillContext context, @agentClass::color
    else if @drawWithPixels
      @drawScaledPixels context
    else
      super context

# #### Patch grid coord system utilities:
  
  # Return the patch id/index given integer x, y in patch coords
  patchIndex: (x, y) -> x - @minX + @numX * (@maxY - y)

  # Return the patch at matrix position x, y where 
  # x & y are both valid integer patch coordinates.
  patchXY: (x, y) -> @[@patchIndex x, y]
  
  # Return x, y float values to be between min/max patch coord values
  clamp: (x, y) ->
    [u.clamp(x, @minXcor, @maxXcor), u.clamp(y, @minYcor, @maxYcor)]
  
  # Return x, y float values to be modulo min/max patch coord values.
  wrap: (x, y) ->
    [u.wrap(x, @minXcor, @maxXcor), u.wrap(y, @minYcor, @maxYcor)]
  
  # Return x, y float values to be between min/max patch values
  # using either clamp/wrap above according to isTorus topology.
  coord: (x, y) -> #returns a valid world coord (real, not int)
    if @isTorus then @wrap x, y else @clamp x, y

  # Return true if on world or torus, false if non-torus and off-world
  isOnWorld: (x, y) ->
    @isTorus or (@minXcor <= x <= @maxXcor and @minYcor <= y <= @maxYcor)

  # Return patch at x, y float values according to topology.
  patch: (x, y) ->
    [x, y] = @coord x, y
    x = u.clamp Math.round(x), @minX, @maxX
    y = u.clamp Math.round(y), @minY, @maxY
    @patchXY x, y
  
  # Return a random valid float x, y point in patch space
  randomPoint: ->
    [u.randomFloat(@minXcor, @maxXcor), u.randomFloat(@minYcor, @maxYcor)]

# #### Patch metrics
  
  # Convert patch measure to pixels
  toBits: (patch) ->
    patch * @size

  # Convert bit measure to patches
  fromBits: (b) -> b / @size

# #### Patch utilities
  
  # Return an array of patches in a rectangle centered on the given 
  # patch `patch`, dx, dy units to the right/left and up/down. 
  # Exclude `patch` unless meToo is true, default false.
  patchRectangle: (patch, dx, dy, meToo = false) ->
    rectangle = @patchRectangleNullPadded(patch, dx, dy, meToo)
    u.remove(rectangle, null)

  patchRectangleNullPadded: (patch, dx, dy, meToo = false) ->
    return patch.pRectangle if patch.pRectangle? and patch.pRectangle.radius is dx
    # and patch.pRectangle.radius is dy
    rectangle = []; # REMIND: optimize if no wrapping, rectangle inside patch boundaries
    for y in [(patch.y - dy)..(patch.y + dy)] by 1 # by 1: perf: avoid bidir JS for loop
      for x in [(patch.x - dx)..(patch.x + dx)] by 1
        nextPatch = null
        if @isTorus
          if x < @minX
            x += @numX
          if x > @maxX
            x -= @numX
          if y < @minY
            y += @numY
          if y > @maxY
            y -= @numY
          nextPatch = @patchXY x, y
        else if x >= @minX and x <= @maxX and
            y >= @minY and y <= @maxY
          nextPatch = @patchXY x, y

        if (meToo or patch isnt nextPatch)
          rectangle.push nextPatch

    @asSet rectangle

  # Draws, or "imports" an image URL into the drawing layer.
  # The image is scaled to fit the drawing layer.
  #
  # This is an async load, see this
  # [new Image()](http://javascript.mfields.org/2011/creating-an-image-in-javascript/)
  # tutorial.  We draw the image into the drawing layer as
  # soon as the onload callback executes.
  importDrawing: (imageSrc, f) ->
    u.importImage imageSrc, (img) => # fat arrow, this context
      @installDrawing img
      f() if f?

  # Direct install image into the given context, not async.
  installDrawing: (img, context = ABM.contexts.drawing) ->
    u.setIdentity context
    context.drawImage img, 0, 0, context.canvas.width, context.canvas.height
    context.restore() # restore patch transform
  
  # Utility function for pixel manipulation.  Given a patch, returns the 
  # native canvas index i into the pixel data.
  # The top-left order simplifies finding pixels in data sets
  pixelByteIndex: (patch) -> 4 * patch.id # Uint8

  pixelWordIndex: (patch) -> patch.id   # Uint32

  # Convert pixel location (top/left offset i.e. mouse) to patch coords (float)
  pixelXYtoPatchXY: (x, y) -> [@minXcor + (x / @size), @maxYcor - (y / @size)]

  # Convert patch coords (float) to pixel location (top/left offset i.e. mouse)
  patchXYtoPixelXY: (x, y) -> [( x - @minXcor) * @size, (@maxYcor - y) * @size]
    
  # Draws, or "imports" an image URL into the patches as their color property.
  # The drawing is scaled to the number of x, y patches, thus one pixel
  # per patch.  The colors are then transferred to the patches.
  # Map is a color map, only for gray for now
  importColors: (imageSrc, f, map) ->
    u.importImage imageSrc, (img) => # fat arrow, this context
      @installColors(img, map)
      f() if f?

  # Direct install image into the patch colors, not async.
  installColors: (img, map) ->
    u.setIdentity @pixelsContext
    @pixelsContext.drawImage img, 0, 0, @numX, @numY # scale if needed
    data = @pixelsContext.getImageData(0, 0, @numX, @numY).data
    for patch in @
      i = @pixelByteIndex patch
      # promote initial default
      patch.color = if map? then map[i] else [data[i++], data[i++], data[i]]
    @pixelsContext.restore() # restore patch transform

  # Draw the patches via pixel manipulation rather than 2D drawRect.
  # See Mozilla pixel [manipulation article](http://goo.gl/Lxliq)
  drawScaledPixels: (context) ->
    # u.setIdentity context & context.restore() only needed if patch size 
    # not 1, pixel ops don't use transform but @size>1 uses
    # a drawimage
    u.setIdentity context if @size isnt 1
    if @pixelsData32? then @drawScaledPixels32 context else @drawScaledPixels8 context
    context.restore() if @size isnt 1

  # The 8-bit version for drawScaledPixels.  Used for systems w/o typed arrays
  drawScaledPixels8: (context) ->
    data = @pixelsData
    for patch in @
      i = @pixelByteIndex patch
      c = patch.color
      if c.length is 4
        a = c[3]
      else
        a = 255
      data[i + j] = c[j] for j in [0..2]
      data[i + 3] = a
    @pixelsContext.putImageData @pixelsImageData, 0, 0
    return if @size is 1
    context.drawImage @pixelsContext.canvas, 0, 0, context.canvas.width, context.canvas.height

  # The 32-bit version of drawScaledPixels, with both little and big endian hardware.
  drawScaledPixels32: (context) ->
    data = @pixelsData32
    for p in @
      i = @pixelWordIndex p
      c = patch.color
      a = if c.length is 4 then c[3] else 255
      if @pixelsAreLittleEndian
      then data[i] = (a << 24) | (c[2] << 16) | (c[1] << 8) | c[0]
      else data[i] = (c[0] << 24) | (c[1] << 16) | (c[2] << 8) | a
    @pixelsContext.putImageData @pixelsImageData, 0, 0
    return if @size is 1
    context.drawImage @pixelsContext.canvas, 0, 0, context.canvas.width, context.canvas.height

  floodFillOnce: (aset, fCandidate, fJoin, fCallback, fNeighbors = ((patch) -> patch.n),
      asetLast = []) ->
    super aset, fCandidate, fJoin, fCallback, fNeighbors, asetLast

  # Diffuse the value of patch variable `patch.v` by distributing `rate` percent
  # of each patch's value of `v` to its neighbors. If a color `c` is given,
  # scale the patch's color to be `patch.v` of `c`. If the patch has
  # less than 8 neighbors, return the extra to the patch.
  diffuse: (v, rate, c) -> # variable name, diffusion rate, max color (optional)
    # zero temp variable if not yet set
    unless @[0]._diffuseNext?
      patch._diffuseNext = 0 for patch in @
    # pass 1: calculate contribution of all patches to themselves and neighbors
    for patch in @
      dv = patch[v] * rate
      dv8 = dv / 8
      nn = patch.neighbors().length
      patch._diffuseNext += patch[v] - dv + (8 - nn) * dv8
      for neighbor in patch.neighbors()
        neighbor._diffuseNext += dv8
    # pass 2: set new value for all patches, zero temp, modify color if c given
    for patch in @
      patch[v] = patch._diffuseNext
      patch._diffuseNext = 0
      if c
        patch.fractionOfColor c, patch[v]
    null # avoid returning copy of @
