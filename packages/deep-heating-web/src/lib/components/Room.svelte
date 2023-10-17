<script lang="ts">
  import { apiClientStore } from '$lib/stores/apiClient';
  import { formatTemperature } from '$lib/temperature';
  import Fire from '$packages/svelte-material-icons/Fire.svelte';
  import type {
    RoomAdjustment,
    RoomState,
  } from '@home-automation/deep-heating-types';
  import { Option, pipe } from 'effect';
  import RoomControls from './RoomControls.svelte';

  export let room: RoomState;

  const isHeating = pipe(
    room.isHeating,
    Option.getOrElse(() => false)
  );

  const adjust: (adjustment: RoomAdjustment) => RoomAdjustment = (
    adjustment: RoomAdjustment
  ) => {
    if ($apiClientStore) $apiClientStore.emit('adjust_room', adjustment);
    return adjustment;
  };
</script>

<div
  class="card card-compact w-44"
  class:bg-heating={isHeating}
  class:bg-cooling={!isHeating}
  style="color: white;"
>
  <div class="card-body">
    <div class="card-title">
      {room.name}
      <div class="card-actions">
        {#if isHeating}
          <Fire />
        {/if}
      </div>
    </div>
    <div class="stat-value text-right">
      {formatTemperature(
        pipe(
          room.temperature,
          Option.map((t) => t.temperature)
        )
      )}
    </div>
    {#if Option.isSome(room.targetTemperature)}
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
