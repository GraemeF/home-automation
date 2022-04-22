<script lang="ts">
  import type { RoomState } from '@home-automation/deep-heating-types';
  import Fire from '$packages/svelte-material-icons/Fire.svelte';
  import { formatTemperature } from '$lib/temperature';
  import RoomControls from './RoomControls.svelte';

  export let room: RoomState;
</script>

<div
  class="card card-compact text-primary-content w-40"
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
    {#if room.targetTemperature}
      <div class="card-actions justify-center items-center">
        <RoomControls {room} />
      </div>
    {/if}
  </div>
</div>
