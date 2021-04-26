SCREEN_W = 320
SCREEN_H = 180
ONE_METER = 15
TREASURE_DEPTH = 50

def vector_length(vector)
  Math.sqrt(vector.x**2 + vector.y**2)
end

def clamp_vector(vector, max_length)
  length = vector_length(vector)
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
        swim_up: keyboard.key_down.up,
        horizontal: keyboard.left_right,
        harpoon: keyboard.key_down.space,
        confirm: keyboard.key_down.space
      }
    end
  end
end

module Game
  class << self
    def setup(args)
      args.state.player = args.state.new_entity_strict(
        :player,
        position: [160, -30],
        v: [0, 0],
        x_forward: 1,
        max_v: 1,
        gravity: -0.01,
        death_tick_count: nil
      )
      args.state.harpoon = args.state.new_entity_strict(
        :harpoon,
        attached: true,
        position: [0, 0],
        v: [0, 0],
        x_forward: 1,
        max_v: 3,
        gravity: 0,
        pulling: false,
        rope_length: 50
      )
      args.state.depth = 0
      args.state.explored_depth = 0
      args.state.enemies = []
      args.state.title_screen = true
    end

    def build_enemy(args, y)
      args.state.new_entity_strict(
        :bite_fish,
        rect: [30 + (rand * (SCREEN_W - 30)).ceil , y, 20, 11],
        w: 20,
        h: 15,
        x_forward: 1,
        death_tick_count: nil
      )
    end

    def player_rect(args)
      position = player_position(args)
      { x: position.x - 11, y: position.y, w: 21, h: 12 }
    end

    def player_is_dead?(args)
      !player(args).death_tick_count.nil?
    end

    def player_collider(args)
      player = player(args)
      position = player_position(args)
      { x: position.x - 11, y: position.y + 1, w: 19, h: 9 }.tap { |result|
        result.x += 2 if player.x_forward.negative?
      }
    end

    def tick(args, input_events)
      if args.state.title_screen
        start_game_on_key_press(args, input_events)
        return
      end

      if player_is_dead?(args)
        reset_game_on_key_press(args, input_events)
      else
        do_swim(args, input_events)
        handle_shoot_harpoon(args, input_events)
        handle_pull_in_harpoon(args, input_events)
      end

      apply_water_resistance(args)
      apply_gravity(args)
      apply_velocity(args)
      apply_harpoon_rope(args)
      kill_enemies_with_harpoon(args)
      kill_player_on_enemy_touch(args)

      move_enemies(args)

      keep_player_inside_screen(args)
      vertical_scroll(args)
    end

    def player(args)
      args.state.player
    end

    def player_position(args)
      player(args).position
    end

    def harpoon(args)
      args.state.harpoon
    end

    def harpoon_position(args)
      harpoon = harpoon(args)
      harpoon.attached ? harpoon_attached_position(args) : harpoon.position
    end

    def harpoon_attached_position(args)
      harpoon = harpoon(args)
      player = player(args)
      player_position = player_position(args)
      [
        player.x_forward.negative? ? player_position.x - 15 : player_position.x + 10,
        Game.player_is_dead?(args) ? player.position.y + 9 : player_position.y + 2
      ]
    end

    def visible_enemies(args)
      screen_top = -args.state.depth
      screen_bottom = screen_top - SCREEN_H

      args.state.enemies.select do |enemy|
        enemy.rect.bottom <= screen_top && enemy.rect.top >= screen_bottom
      end
    end

    private

    def do_swim(args, input_events)
      horizontal_movement = input_events[:horizontal]
      player = player(args)
      player.v.y += 0.5 if input_events[:swim_up]
      player.v.x = horizontal_movement * 0.5
      player.x_forward = horizontal_movement.sign unless horizontal_movement.zero?

      harpoon = Game.harpoon(args)
      harpoon.x_forward = player.x_forward if harpoon.attached
    end

    def handle_shoot_harpoon(args, input_events)
      harpoon = harpoon(args)
      return unless harpoon.attached && input_events[:harpoon]

      player = Game.player(args)
      harpoon.position = harpoon_attached_position(args)
      harpoon.v.x = player.v.x + harpoon.x_forward * 3
      harpoon.v.y = player.v.y
      harpoon.gravity = -0.005
      harpoon.attached = false

      input_events[:harpoon] = false
    end

    def handle_pull_in_harpoon(args, input_events)
      harpoon = harpoon(args)
      return unless !harpoon.attached && !harpoon.pulling && input_events[:harpoon]

      harpoon.pulling = true
      harpoon.gravity = 0
    end

    def apply_water_resistance(args)
      harpoon = harpoon(args)
      return if harpoon.attached || harpoon.v.x.zero?

      harpoon.v.x *= 0.95
      harpoon.v.x = 0 if harpoon.v.x.abs < 0.01
    end

    def apply_harpoon_rope(args)
      harpoon = harpoon(args)
      return if harpoon.attached

      attached_position = harpoon_attached_position(args)
      harpoon_to_player = [attached_position.x - harpoon.position.x, attached_position.y - harpoon.position.y]
      distance = vector_length(harpoon_to_player)

      if harpoon.pulling
        harpoon.v.x = 2 * harpoon_to_player.x / distance
        harpoon.v.y = 2 * harpoon_to_player.y / distance
        return unless distance < 3

        harpoon.attached = true
        harpoon.pulling = false
      else
        return if distance < harpoon.rope_length

        factor = (distance - harpoon.rope_length) / distance
        harpoon.position.x += harpoon_to_player.x * factor
        harpoon.position.y += harpoon_to_player.y * factor
      end
    end

    def apply_gravity(args)
      [player(args), harpoon(args)].each do |gravity_object|
        gravity_object.v.y += gravity_object.gravity
      end
    end

    def apply_velocity(args)
      [player(args), harpoon(args)].each do |moving_object|
        clamp_vector(moving_object.v, moving_object.max_v)
        moving_object.position.x += moving_object.v.x
        moving_object.position.y += moving_object.v.y
      end
    end

    def keep_player_inside_screen(args)
      player_position = player_position(args)
      player_rect = player_rect(args)
      player_position.x += -player_rect.left if player_rect.left.negative?
      player_position.x -= (player_rect.right - SCREEN_W) if player_rect.right > SCREEN_W
      player_position.y -= player_rect.top if player_rect.top.positive?
      player_position.y += (-TREASURE_DEPTH * ONE_METER - player_rect.bottom) if player_rect.bottom < -TREASURE_DEPTH * ONE_METER
    end

    def vertical_scroll(args)
      args.state.depth = [0, (player_position(args).y.abs - SCREEN_H.half).to_i].max
      args.state.depth = [TREASURE_DEPTH * ONE_METER - SCREEN_H + 20, args.state.depth].min
      if args.state.depth > args.state.explored_depth + 20
        args.state.explored_depth = args.state.depth

        remove_old_enemies(args)
        add_new_enemies(args)
      end
    end

    def remove_old_enemies(args)
      args.state.enemies.reject! { |enemy| enemy.rect.y > -args.state.explored_depth + SCREEN_H * 3 }
    end

    def add_new_enemies(args)
      min_enemy_distance = 100 - args.state.depth.div(ONE_METER * 20) * 5
      next_enemy_y = -args.state.depth - SCREEN_H - 40
      closest_enemy = args.state.enemies.last
      return if closest_enemy && (closest_enemy.rect.y - next_enemy_y) < min_enemy_distance

      args.state.enemies << build_enemy(args, next_enemy_y + (rand * 20).ceil)
    end

    def move_enemies(args)
      args.state.enemies.each do |enemy|
        if enemy.death_tick_count
          # float up dead
          enemy.rect.y += (args.tick_count - enemy.death_tick_count) * 0.02
        else
          enemy.rect.x += enemy.x_forward
          if enemy.x_forward.positive? && enemy.rect.right > SCREEN_W - 20 || enemy.x_forward.negative? && enemy.rect.left < 20
            enemy.x_forward *= -1
          end
        end
      end
    end

    def kill_enemies_with_harpoon(args)
      args.state.enemies.reject! { |enemy|
        enemy.death_tick_count && args.tick_count - enemy.death_tick_count > 20
      }

      harpoon = harpoon(args)
      return if harpoon.attached || harpoon.v.x.abs < 1

      args.state.enemies.each do |enemy|
        next unless harpoon.position.inside_rect? enemy.rect

        enemy.death_tick_count = args.tick_count
      end
    end

    def kill_player_on_enemy_touch(args)
      player_collider = player_collider(args)

      touched_enemy = args.state.enemies.any? { |enemy|
        next false if enemy.death_tick_count

        enemy.rect.intersect_rect? player_collider
      }

      player(args).death_tick_count = args.tick_count if touched_enemy
    end

    def reset_game_on_key_press(args, input_events)
      return unless input_events[:confirm]

      args.state.should_reset = true
    end

    def start_game_on_key_press(args, input_events)
      return unless input_events[:confirm]

      args.state.title_screen = false
    end
  end
end

module Render
  class << self
    def setup(args)
      args.state.rock_seed = Time.now.to_i
      args.state.palette = [
        { r: 55, g: 33, b: 52 },
        { r: 71, g: 68, b: 118 },
        { r: 72, g: 136, b: 183 },
        { r: 109, g: 188, b: 185 },
        { r: 140, g: 239, b: 182 }
      ]
      args.outputs.static_primitives << {
        x: 0, y: 0, w: 1280, h: 720,
        source_x: 0, source_y: 0, source_w: SCREEN_W, source_h: SCREEN_H,
        path: :canvas
      }.sprite
    end

    def tick(args)
      render_target = args.outputs[:canvas]
      bg_color = args.state.palette[2]
      render_target.background_color = [bg_color.r, bg_color.g, bg_color.b]

      unless args.state.title_screen
        render_enemies(args, render_target)
        render_player(args, render_target)
        render_harpoon(args, render_target)
        render_harpoon_rope(args, render_target)
      end

      render_rocks(args, render_target)

      render_floor(args, render_target)

      transform_for_depth(args, render_target)

      if args.state.title_screen
        render_title_screen(args, render_target)
      else
        render_ui(args, render_target)
      end
    end

    private

    def y_on_screen(args, y)
      top = -args.state.depth
      SCREEN_H - (top - y)
    end

    def transform_for_depth(args, render_target)
      render_target.primitives.each do |primitive|
        primitive.y = y_on_screen(args, primitive.y)
        primitive.y2 = y_on_screen(args, primitive.y2) if primitive.primitive_marker == :line
      end
    end

    def render_player(args, render_target)
      player = Game.player(args)
      is_dead = Game.player_is_dead?(args)
      base = Game.player_rect(args).merge(
        path: 'resources/player.png',
        source_x: args.tick_count.idiv(10) % 2 == 0 ? 0 : 21,
        source_w: 21,
        source_h: 12,
        flip_horizontally: player.x_forward < 0,
        flip_vertically: is_dead
      ).sprite
      render_target.primitives << base.merge(source_y: 12).merge(args.state.palette[0])
      render_target.primitives << base.merge(source_y: 0).merge(args.state.palette[4])
      return unless Debug.debug_mode

      render_target.primitives << Game.player_collider(args).merge(r: 255).border
    end

    def render_harpoon(args, render_target)
      player_position = Game.player_position(args)
      harpoon = Game.harpoon(args)
      harpoon_position = Game.harpoon_position(args)
      flip_horizontally = harpoon.x_forward.negative?
      x = flip_horizontally ? harpoon_position.x - 2 : harpoon_position.x - 5
      y = harpoon_position.y - 2
      render_target.primitives << {
        x: x,
        y: y,
        flip_horizontally: flip_horizontally,
        w: 8,
        h: 5,
        path: 'resources/harpoon.png'
      }.merge(args.state.palette[4]).sprite
      return unless Debug.debug_mode

      render_target.primitives << { x: harpoon_position.x, y: harpoon_position.y, w: 1, h: 1, r: 255, g: 0, b: 0 }.solid
    end

    def render_harpoon_rope(args, render_target)
      harpoon = Game.harpoon(args)
      return if harpoon.attached

      player = Game.player(args)
      player_position = Game.player_position(args)

      render_target.primitives << {
        x: harpoon.x_forward.positive? ? harpoon.position.x - 5 : harpoon.position.x + 5,
        y: harpoon.position.y + 1,
        x2: player.x_forward.positive? ? player_position.x + 8 : player_position.x - 9,
        y2: Game.player_is_dead?(args) ? player_position.y + 8 : player_position.y + 4
      }.merge(args.state.palette[4]).line
    end

    def render_enemies(args, render_target)
      Game.visible_enemies(args).each do |enemy|
        is_dead = !enemy.death_tick_count.nil?

        render_target.primitives << {
          x: enemy.rect.x,
          y: enemy.rect.y,
          w: enemy.w,
          h: enemy.h,
          path: "resources/#{enemy.entity_type}.png",
          source_x: (is_dead || args.tick_count.idiv(10) % 2 == 0) ? 0 : enemy.rect.w,
          source_y: 0,
          source_w: enemy.w,
          source_h: enemy.h,
          flip_horizontally: enemy.x_forward.negative?,
          flip_vertically: is_dead,
          a: 255 - (is_dead ? (args.tick_count - enemy.death_tick_count) * 13 : 0)
        }.merge(args.state.palette[3]).sprite

        next unless Debug.debug_mode

        render_target.primitives << [*enemy.rect, 255].border
      end
    end

    def render_rocks(args, render_target)
      start_y_above = -(args.state.depth.idiv(SCREEN_H) - 1) * SCREEN_H
      render_rocks_segment(args, render_target, start_y_above)
      render_rocks_segment(args, render_target, start_y_above - SCREEN_H)
      render_rocks_segment(args, render_target, start_y_above - SCREEN_H * 2)
      render_rocks_segment(args, render_target, start_y_above - SCREEN_H * 3)
    end

    def render_rocks_segment(args, render_target, start_y)
      rng = Random.new(args.state.rock_seed + start_y)
      base = {
        w: 48,
        h: 48,
        path: 'resources/rock.png',
        source_y: 0,
        source_w: 48,
        source_h: 48,
      }.merge(args.state.palette[0]).sprite

      y = start_y
      loop do
        y -= (10 + (rng.rand * 20).ceil)
        render_target.primitives << base.merge(
          x: (rng.rand * 20).ceil - 30,
          y: y,
          source_x: (rng.rand * 4).floor * 48,
          flip_horizontally: rng.rand < 0.5,
          flip_vertically: rng.rand < 0.5,
        )
        break if y < start_y - SCREEN_H
      end

      y = start_y
      loop do
        y -= (10 + (rng.rand * 20).ceil)
        render_target.primitives << base.merge(
          x: SCREEN_W - 20 - (rng.rand * 20).ceil,
          y: y,
          source_x: (rng.rand * 4).floor * 48,
          flip_horizontally: rng.rand < 0.5,
          flip_vertically: rng.rand < 0.5
        )
        break if y < start_y - SCREEN_H
      end
    end

    def base_font(args)
      base_font = {
        font: 'resources/8_bit_fortress/8-bit fortress.ttf'
      }.merge(args.state.palette[4]).label
    end

    def render_ui(args, render_target)
      base_font = base_font(args)

      meters = Game.player_position(args).y.abs.idiv(ONE_METER * 10) * 10
      render_target.primitives << base_font.merge(
        x: SCREEN_W,
        y: SCREEN_H,
        text: "#{meters}m",
        alignment_enum: 2,
        size_enum: -7,
      )

      return unless Game.player_is_dead?(args)

      render_target.primitives << base_font.merge(
        x: SCREEN_W.half,
        y: SCREEN_H.half + 20,
        text: "You died.",
        alignment_enum: 1,
        size_enum: -3,
      )
      render_target.primitives << base_font.merge(
        x: SCREEN_W.half,
        y: SCREEN_H.half,
        text: "Press [SPACE] to restart",
        alignment_enum: 1,
        size_enum: -3,
      )
    end

    def render_title_screen(args, render_target)
      base_font = base_font(args)

      render_target.primitives << base_font.merge(
        x: SCREEN_W.half,
        y: SCREEN_H.half + 60,
        text: "Descent to",
        alignment_enum: 1,
        size_enum: 1,
      )
      render_target.primitives << base_font.merge(
        x: SCREEN_W.half,
        y: SCREEN_H.half + 30,
        text: "Midnight Trench",
        alignment_enum: 1,
        size_enum: 1,
      )
      render_target.primitives << base_font.merge(
        x: SCREEN_W.half,
        y: SCREEN_H.half - 30,
        text: "Press [SPACE] to play",
        alignment_enum: 1,
        size_enum: -3,
      )
    end

    def render_floor(args, render_target)
      return if args.state.depth < TREASURE_DEPTH * ONE_METER - SCREEN_H * 2

      depth = -TREASURE_DEPTH * ONE_METER
      render_target.primitives << {
        x: 0,
        y: depth - 20,
        w: SCREEN_W,
        h: 20
      }.merge(args.state.palette[0]).solid
      render_target.primitives << {
        x: SCREEN_W.half - 9,
        y: depth,
        w: 17,
        h: 19,
        path: 'resources/treasure_outline.png'
      }.merge(args.state.palette[4]).sprite
      render_target.primitives << {
        x: SCREEN_W.half - 9,
        y: depth,
        w: 17,
        h: 19,
        path: 'resources/treasure.png'
      }.merge(args.state.palette[1]).sprite
    end
  end
end

module Debug
  class << self
    attr_accessor :debug_mode

    def tick(args)
      return unless active?

      args.outputs.debug << [0, 720, $gtk.current_framerate.to_i.to_s, 255, 255, 255].label
      $gtk.reset if args.inputs.keyboard.key_down.r
      self.debug_mode = !self.debug_mode if args.inputs.keyboard.key_down.d
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
  $gtk.reset if args.state.should_reset
end

$gtk.reset
$console.close
