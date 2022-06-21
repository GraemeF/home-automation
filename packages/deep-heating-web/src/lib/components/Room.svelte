<script lang="ts">
  import type { RoomState } from '@home-automation/deep-heating-types';
  import Fire from '$packages/svelte-material-icons/Fire.svelte';
  import { formatTemperature } from '$lib/temperature';
  import RoomControls from './RoomControls.svelte';
  import type { RoomAdjustment } from '@home-automation/deep-heating-types';
  import { apiClientStore } from '$lib/stores/apiClient';

  export let room: RoomState;

  const adjust: (adjustment: RoomAdjustment) => RoomAdjustment = (
    adjustment: RoomAdjustment
  ) => {
    $apiClientStore.emit('adjust_room', adjustment);
    return adjustment;
  };
</script>

<div
  class="card card-compact text-primary-content w-44"
  class:bg-heating={room.isHeating}
  class:bg-cooling={!room.isHeating}
>
  <div class="card-body">
    <a href="/deep-heating/rooms/{room.name}">
      <div class="card-title">
        {room.name}
        <div class="card-actions">
          {#if room.isHeating}
            <Fire />
          {/if}
        </div>
      </div>
      <div class="stat-value text-right">
        {formatTemperature(room.temperature.temperature)}
      </div>
    </a>
    {#if room.targetTemperature}
      <div class="card-actions justify-center items-center">
        <RoomControls
          {room}
          adjustment={room.adjustment}
          adjust={(newAdjustment) =>
            adjust({
              roomName: room.name,
              adjustment: newAdjustment,
            })}
        />
      </div>
    {/if}
  </div>
</div>
