def clamp_vector(vector, max_length)
  length = Math.sqrt(vector.x**2 + vector.y**2)
  return if length <= max_length

  factor = max_length / length
  vector.x *= factor
  vector.y *= factor
end

module Input
  class << self
    def process(args)
      keyboard = args.inputs.keyboard
      {
        swim_up: keyboard.key_down.space,
        horizontal: keyboard.left_right
      }
    end
  end
end

module Game
  class << self
    def setup(args)
      args.state.player = args.state.new_entity_strict(
        :player,
        position: [180, 140],
        v: [0, 0],
        x_forward: 1
      )
    end

    def player_rect(args)
      position = player_position(args)
      { x: position.x - 11, y: position.y, w: 21, h: 12 }
    end

    def tick(args, input_events)
      do_swim(args, input_events)
      apply_gravity(args)
      apply_velocity(args)
      keep_player_inside_screen(args)
    end

    def player(args)
      args.state.player
    end

    def player_position(args)
      player(args).position
    end

    private

    MAX_V = 1

    def do_swim(args, input_events)
      horizontal_movement = input_events[:horizontal]
      player = player(args)
      player.v.y += 0.5 if input_events[:swim_up]
      player.v.x = horizontal_movement * 0.5
      player.x_forward = horizontal_movement.sign unless horizontal_movement.zero?
    end

    def apply_gravity(args)
      player = player(args)
      player.v.y -= 0.01
    end

    def apply_velocity(args)
      player = player(args)
      clamp_vector(player.v, MAX_V)
      player.position.x += player.v.x
      player.position.y += player.v.y
    end

    def keep_player_inside_screen(args)
      player_position = player_position(args)
      player_rect = player_rect(args)
      player_position.x += -player_rect.left if player_rect.left.negative?
      player_position.x -= (player_rect.right - 320) if player_rect.right > 320
    end
  end
end

module Render
  class << self
    def setup(args)
      args.state.palette = [
        { r: 55, g: 33, b: 52 },
        { r: 71, g: 68, b: 118 },
        { r: 72, g: 136, b: 183 },
        { r: 109, g: 188, b: 185 },
        { r: 140, g: 239, b: 182 }
      ]
      args.outputs.static_primitives << {
        x: 0, y: 0, w: 1280, h: 720,
        source_x: 0, source_y: 0, source_w: 320, source_h: 180,
        path: :canvas
      }.sprite
    end

    def tick(args)
      render_target = args.outputs[:canvas]
      bg_color = args.state.palette[2]
      render_target.background_color = [bg_color.r, bg_color.g, bg_color.b]
      render_player(args, render_target)
    end

    private

    def render_player(args, render_target)
      player = Game.player(args)
      base = Game.player_rect(args).merge(
        path: 'resources/player.png',
        source_x: args.tick_count.idiv(10) % 2 == 0 ? 0 : 21,
        source_w: 21,
        source_h: 12,
        flip_horizontally: player.x_forward < 0
      ).sprite
      render_target.primitives << base.merge(source_y: 12).merge(args.state.palette[0])
      render_target.primitives << base.merge(source_y: 0).merge(args.state.palette[4])
    end
  end
end

module Debug
  class << self
    def tick(args)
      return unless active?

      args.outputs.debug << [0, 720, $gtk.current_framerate.to_i.to_s, 255, 255, 255].label
      $gtk.reset if args.inputs.keyboard.key_down.r
    end

    private

    def active?
      !$gtk.production
    end
  end
end

def setup(args)
  Game.setup(args)
  Render.setup(args)
end

def tick(args)
  setup(args) if args.tick_count.zero?
  Game.tick(args, Input.process(args))
  Render.tick(args)
  Debug.tick(args)
end

$gtk.reset
$console.close
