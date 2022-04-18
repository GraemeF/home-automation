<script lang="ts">
  import type { RoomState } from '@home-automation/deep-heating-types';
  import Fire from '$packages/svelte-material-icons/Fire.svelte';
  import { formatTemperature } from '$lib/temperature';

  export let room: RoomState;
</script>

<div
  class="card-compact text-primary-content w-44"
  class:bg-heating={room.isHeating}
  class:bg-cooling={!room.isHeating}
>
  <div class="card-body">
    <div class="card-title">
      {room.name}
      <div class="card-actions">
        {#if room.isHeating}
          <Fire />
        {/if}
      </div>
    </div>
    <div class="stat-value">
      {formatTemperature(room.temperature.temperature)}
    </div>
    <div class="card-actions justify-center">
      <div class="stat-desc">{room.adjustment}</div>
    </div>
  </div>
</div>
