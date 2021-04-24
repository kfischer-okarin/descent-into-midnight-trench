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
      args.state.player = { position: [180, 140], v: [0, 0] }
    end

    def player_rect(args)
      position = player(args)[:position]
      { x: position.x - 8, y: position.y, w: 16, h: 32 }
    end

    def tick(args, input_events)
      do_swim(args, input_events)
      apply_gravity(args)
      apply_velocity(args)
    end

    def player(args)
      args.state.player
    end

    private

    MAX_V = 1

    def do_swim(args, input_events)
      player = player(args)
      player[:v].y += 0.5 if input_events[:swim_up]
      player[:v].x = (input_events[:horizontal] || 0) * 0.5
    end

    def apply_gravity(args)
      player = player(args)
      player[:v].y -= 0.01
    end

    def clamp(vector, max_length)
      length = Math.sqrt(vector.x**2 + vector.y**2)
      return if length <= max_length

      factor = max_length / length
      vector.x *= factor
      vector.y *= factor
    end

    def apply_velocity(args)
      player = player(args)
      clamp(player[:v], MAX_V)
      player[:position].x += player[:v].x
      player[:position].y += player[:v].y
    end
  end
end

module Render
  class << self
    def setup(args)
      args.outputs.static_primitives << {
        x: 0, y: 0, w: 1280, h: 720,
        source_x: 0, source_y: 0, source_w: 320, source_h: 180,
        path: :canvas
      }.sprite
    end

    def tick(args)
      render_target = args.outputs[:canvas]
      render_target.background_color = [0, 0, 0]
      render_player(args, render_target)
    end

    private

    def render_player(args, render_target)
      render_target.primitives << Game.player_rect(args).merge(r: 255, g: 0, b: 0).solid
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
