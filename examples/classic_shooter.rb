# A simple Gorilla-style shooter for two players.
# Shows how Gosu to generate a map, implement
# a dynamic landscape and generally look great.
# Also shows a very minimal, yet effective way of designing a game's object system.

# Doesn't make use of Gosu's Z-ordering. Not many different things to draw, it's
# easy to get the order right without it.

# Known issues:
# * Collision detection of the missiles is lazy, allows shooting through thin walls.
# * The look of dead soldiers is, err, by accident. Soldier.png needs to be
#   designed in a less obfuscated way :)

WIDTH  = 640
HEIGHT = 480

GAME_PATH = File.expand_path("..", __FILE__)
SMOKE     = Gosu::Image.new("#{GAME_PATH}/media/smoke.png")

# The class for this game's map.
# Design:
# * Dynamic map creation at startup, holding it as a Gosu::Image in @image
# * Testing for solidity by testing @image's pixel values
# * Drawing from a Gosu::Image instance
# * Blasting holes into the map is implemented by inserting transparent
#   image strips generated by `generate_circle`

class Map
  # Radius of a crater.
  CRATER_RADIUS = 25
  # Radius of a crater, Shadow included.
  SHADOW_RADIUS = 45

  def initialize
    @sky = Gosu::Image.new("#{GAME_PATH}/media/landscape.png", tileable: true)
    @image = Gosu.render(1, 1) { }

    # Generate a bunch of single pixel width images used to dig out the craters
    @crater_segments = generate_circle(CRATER_RADIUS)

    # Create the map
    @binary_map = []
    create_map
    extract_map_pixels
  end

  def generate_circle(radius, color = Gosu::Color::NONE)
    images = []

    width = radius * 2
    height = 0
    x2 = 0

    width.times do |i|
      x2 = i
      height = 0

      radius.times do |j|
        if (Gosu.distance(radius, radius, x2, j) < radius)
          height = radius - j
          break
        end
      end

      y2 = radius - height
      y3 = radius + height

      _height = (y3 - y2) == 0 ? 1 : (y3 - y2)
      images << Gosu.render(1, _height) do
        Gosu.draw_line(1, 0, color, 1, _height, color)
      end
    end

    return images
  end

  def pixel_solid?(x, y)
    @binary_map[(x + WIDTH * y)]
  end

  def solid?(x, y)
    # Map is open at the top.
    return false if y < 0
    # Map is closed on all other sides.
    return true if x < 0 || x >= WIDTH || y >= HEIGHT
    # Inside of the map, determine solidity from the map image.
    pixel_solid?(x, y)
  end

  def draw
    # Sky background.
    @sky.draw(0, 0, 0)
    # The landscape.
    @image.draw(0, 0, 0)
  end

  def blast(x, y)
    @crater_segments.size.times do |i|
      image = @crater_segments[i]
      @image.insert(image, x - (CRATER_RADIUS - i), y - (image.height / 2))
    end

    extract_map_pixels
  end

  private def create_map
    earth = Gosu::Image.new("#{GAME_PATH}/media/earth.png")
    star = Gosu::Image.new("#{GAME_PATH}/media/large_star.png")

    heightmap = []
    seed = rand(0xffffff)
    frequency = 0.01
    amplitude = [25, rand(100)].max

    # Generate a simple curve to make the level not flat
    WIDTH.times do |x|
      heightmap << (amplitude * (Math.cos(frequency * (seed + x)) + 1) / 2).to_i
    end

    strips = Gosu::Image.load_tiles("#{GAME_PATH}/media/earth.png", 1, earth.height)

    # Paint about half the map with the earth texture
    @image = Gosu.render(WIDTH, HEIGHT) do
      ((HEIGHT / 2) / earth.height).ceil.to_i.times do |y|
        WIDTH.times do |x|
          _height = heightmap[x]
          strips[x % earth.width].draw(x, (HEIGHT / 2) + y * earth.height + _height, 0)
        end
      end

      _x = (WIDTH / 2) - (star.width / 2)
      _height = heightmap[_x]
      _y = ((HEIGHT / 2) + _height) - star.height

      star.draw(_x, _y, 0)
    end
  end

  private def extract_map_pixels
    data = @image.to_blob.bytes
    @binary_map.clear

    HEIGHT.times do |y|
      WIDTH.times do |x|
        index = (x + WIDTH * y) * 4
        r, g, b, alpha = data[index, 4]

        @binary_map << (alpha != 0)
      end
    end
  end
end

# Player class.
# Note that applies to the whole game:
# All objects implement an informal interface.
# draw: Draws the object (obviously)
# update: Moves the object etc., returns false if the object is to be deleted
# hit_by?(missile): Returns true if an object is hit by the missile, causing
#                   it to explode on this object.

class Player
  # Magic numbers considered harmful! This is the height of the
  # player as used for collision detection.
  HEIGHT = 14

  attr_reader :x, :y, :dead
  # Only load the images once for all instances of this class.
  @@images = Gosu::Image.load_tiles("#{GAME_PATH}/media/soldier.png", 40, 50)

  def initialize(window, x, y, color)
    @window = window
    @x, @y = x, y
    @color = color

    @vy = 0

    # -1: left, +1: right
    @dir = -1

    # Aiming angle.
    @angle = 90
  end

  def draw
    if dead
      # Poor, broken soldier.
      @@images[0].draw_rot(@x, @y, 0, 290 * @dir, 0.5, 0.65, @dir * 0.5, 0.5, @color)
      @@images[2].draw_rot(@x, @y, 0, 160 * @dir, 0.95, 0.5, 0.5, @dir * 0.5, @color)
    else
      # Was moved last frame?
      if @show_walk_anim
        # Yes: Display walking animation.
        frame = Gosu.milliseconds / 200 % 2
      else
        # No: Stand around (boring).
        frame = 0
      end

      # Draw feet, then chest.
      @@images[frame].draw(x - 10 * @dir, y - 20, 0, @dir * 0.5, 0.5, @color)
      angle = @angle
      angle = 180 - angle if @dir == -1
      @@images[2].draw_rot(x, y - 5, 0, angle, 1, 0.5, 0.5, @dir * 0.5, @color)
    end
  end

  def update
    # First, assume that no walking happened this frame.
    @show_walk_anim = false

    # Gravity.
    @vy += 1

    if @vy > 1
      # Move upwards until hitting something.
      @vy.times do
        if @window.map.solid?(x, y + 1)
          @vy = 0
          break
        else
          @y += 1
        end
      end
    else
      # Move downwards until hitting something.
      (-@vy).times do
        if @window.map.solid?(x, y - HEIGHT - 1)
          @vy = 0
          break
        else
          @y -= 1
        end
      end
    end

    # Soldiers are never deleted (they may die, but that is a different thing).
    return true
  end

  def aim_up
    @angle -= 2 unless @angle < 10
  end

  def aim_down
    @angle += 2 unless @angle > 170
  end

  def try_walk(dir)
    @show_walk_anim = true
    @dir = dir
    # First, magically move up (so soldiers can run up hills)
    2.times { @y -= 1 unless @window.map.solid?(x, y - HEIGHT - 1) }
    # Now move into the desired direction.
    @x += dir unless @window.map.solid?(x + dir, y) ||
                     @window.map.solid?(x + dir, y - HEIGHT)
    # To make up for unnecessary movement upwards, sink downward again.
    2.times { @y += 1 unless @window.map.solid?(x, y + 1) }
  end

  def try_jump
    @vy = -12 if @window.map.solid?(x, y + 1)
  end

  def shoot
    @window.objects << Missile.new(@window, x + 10 * @dir, y - 10, @angle * @dir)
  end

  def hit_by?(missile)
    if Gosu.distance(missile.x, missile.y, x, y) < 30
      # Was hit :(
      @dead = true
      return true
    else
      return false
    end
  end
end

# Implements the same interface as Player, except it's a missile!

class Missile
  attr_reader :x, :y, :vx, :vy

  # All missile instances use the same sound.
  EXPLOSION = Gosu::Sample.new("#{GAME_PATH}/media/explosion.wav")

  def initialize(window, x, y, angle)
    # Horizontal/vertical velocity.
    @window = window
    @x, @y = x, y
    @angle = angle
    @vx, @vy = Gosu.offset_x(angle, 20).to_i, Gosu.offset_y(angle, 20).to_i

    @x, @y = x + @vx, y + @vy
  end

  def update
    # Movement, gravity
    @x += @vx
    @y += @vy
    @vy += 1

    # Hit anything?
    if @window.map.solid?(x, y) || @window.objects.any? { |o| o.hit_by?(self) }
      # Create great particles.
      5.times { @window.objects << Particle.new(x - 25 + rand(51), y - 25 + rand(51)) }
      @window.map.blast(x, y)
      # # Weeee, stereo sound!
      EXPLOSION.play_pan((1.0 * @x / WIDTH) * 2 - 1)

      return false
    else
      return true
    end
  end

  def draw
    # Just draw a small rectangle.
    Gosu.draw_rect x - 2, y - 2, 4, 4, 0xff_800000
  end

  def hit_by?(missile)
    # Missiles can't be hit by other missiles!
    false
  end
end

# Very minimal object that just draws a fading particle.

class Particle
  def initialize(x, y)
    # All Particle instances use the same image
    @x, @y = x, y
    @color = Gosu::Color.new(255, 255, 255, 255)
  end

  def update
    @y -= 5
    @x = @x - 1 + rand(3)
    @color.alpha -= 4

    # Remove if faded completely.
    return @color.alpha > 0
  end

  def draw
    SMOKE.draw(@x - 25, @y - 25, 0, 1, 1, @color)
  end

  def hit_by?(missile)
    # Smoke can't be hit!
    false
  end
end

# Finally, the class that ties it all together.
# Very straightforward implementation.

class ClassicShooter < Gosu::Window
  attr_reader :map, :objects

  def initialize
    super(WIDTH, HEIGHT)

    # Texts to display in the appropriate situations.
    @player_instructions = []
    @player_won_messages = []
    2.times do |plr|
      @player_instructions << Gosu::Image.from_markup(
        "It is the #{plr == 0 ? "<c=ff00ff00>green</c>" : "<c=ffff0000>red</c>"} toy soldier's turn.\n" +
        "(Arrow keys to walk and aim, Control to jump, Space to shoot)",
        30, width: width, align: :center)

      @player_won_messages << Gosu::Image.from_markup(
        "The #{plr == 0 ? "<c=ff00ff00>green</c>" : "<c=ffff0000>red</c>"} toy soldier has won!",
        30, width: width, align: :center)
    end

    # Create everything!
    @map = Map.new
    @players = []
    @objects = []
    @arrow = Gosu.render(32, 64) do
      Gosu.draw_rect(8, 0, 16, 48, Gosu::Color::WHITE)
      Gosu.draw_triangle(0, 48, Gosu::Color::WHITE,
        32, 48, Gosu::Color::WHITE,
        16, 64, Gosu::Color::WHITE,
        0)
    end

    # Let any player start.
    @current_player = rand(2)
    # Currently not waiting for a missile to hit something.
    @waiting = false

    p1, p2 = Player.new(self, 100, 40, 0xff_308000), Player.new(self, WIDTH - 100, 40, 0xff_803000)

    @players.push(p1, p2)
    @objects.push(p1, p2)

    self.caption = "Classic Shooter Demo"
  end

  def draw
    # Draw the main game.
    @map.draw
    @objects.each { |o| o.draw }

    # Draw an arrow over the current players head
    unless @players[@current_player].dead || @waiting
      player = @players[@current_player]

      @arrow.draw(player.x - @arrow.width / 2, player.y - (@arrow.height + 32), 0, 1, 1, Gosu::Color::GRAY)
    end

    # If any text should be displayed, draw it - and add a nice black border around it
    # by drawing it four times, with a little offset in each direction.

    cur_text = @player_instructions[@current_player] if !@waiting
    cur_text = @player_won_messages[1 - @current_player] if @players[@current_player].dead

    if cur_text
      x, y = 0, 30
      cur_text.draw(x - 1, y, 0, 1, 1, 0xff_000000)
      cur_text.draw(x + 1, y, 0, 1, 1, 0xff_000000)
      cur_text.draw(x, y - 1, 0, 1, 1, 0xff_000000)
      cur_text.draw(x, y + 1, 0, 1, 1, 0xff_000000)
      cur_text.draw(x, y, 0, 1, 1, 0xff_ffffff)
    end
  end

  def update
    # if waiting for the next player's turn, continue to do so until the missile has
    # hit something.
    @waiting &&= !@objects.select { |obj| obj.is_a?(Missile) }.empty?

    # Remove all objects whose update method returns false.
    @objects.reject! { |o| o.update == false }

    # If it's a player's turn, forward controls.
    if !@waiting && !@players[@current_player].dead
      player = @players[@current_player]
      player.aim_up if Gosu.button_down? Gosu::KB_UP
      player.aim_down if Gosu.button_down? Gosu::KB_DOWN
      player.try_walk(-1) if Gosu.button_down? Gosu::KB_LEFT
      player.try_walk(+1) if Gosu.button_down? Gosu::KB_RIGHT
      player.try_jump if Gosu.button_down?(Gosu::KB_LEFT_CONTROL) || Gosu.button_down?(Gosu::KB_RIGHT_CONTROL)
    end
  end

  def button_down(id)
    if id == Gosu::KB_SPACE && !@waiting && !@players[@current_player].dead
      # Shoot! This is handled in button_down because holding space shouldn't auto-fire.
      @players[@current_player].shoot
      @current_player = 1 - @current_player
      @waiting = true
    else
      super
    end
  end
end

# So far we have only defined how everything *should* work - now set it up and run it!
ClassicShooter.new.show
