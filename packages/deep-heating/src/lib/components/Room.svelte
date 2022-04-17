<script lang="ts">
  import type { RoomState } from '@home-automation/deep-heating-types';

  export let room: RoomState;
</script>

<div
  class="stat  text-primary-content"
  class:bg-heating={room.isHeating}
  class:bg-cooling={!room.isHeating}
>
  <div class="stat-title">{room.name}</div>
  <div class="stat-value">{room.temperature.temperature}</div>
  <div class="stat-unit">°C</div>
  <div class="stat-desc">{room.adjustment}</div>
</div>
