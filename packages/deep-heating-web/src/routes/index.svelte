<script lang="ts">
  import { homeStore } from '$lib/stores/home';
  import { apiClientStore } from '$lib/stores/apiClient';
  import Spinner from '$lib/components/Spinner.svelte';
  import Heating from '$lib/components/Heating.svelte';
  import Room from '$lib/components/Room.svelte';
  import { compareByRoomTemperature } from '$lib/temperature';
  import type { RoomAdjustment } from '@home-automation/deep-heating-types';

  const adjust: (adjustment: RoomAdjustment) => RoomAdjustment = (
    adjustment: RoomAdjustment
  ) => {
    $apiClientStore.emit('adjust_room', adjustment);
    return adjustment;
  };
</script>

{#if $homeStore.connected}
  <div class="container mx-auto">
    <div class="mx-3.5">
      <div class="flex flex-row justify-between">
        <h1>Deep Heating</h1>
        {#if $homeStore.state}
          <Heating isHeating={$homeStore.state.isHeating} />{/if}
      </div>
      {#if $homeStore.state}
        <div class="flex flex-row flex-wrap gap-2">
          {#each $homeStore.state.rooms.sort(compareByRoomTemperature) as room}
            <Room {room} {adjust} />
          {/each}
        </div>
      {/if}
    </div>
  </div>
{:else}
  <div class="w-full h-full fixed block top-0 left-0 bg-white opacity-75 z-50">
    <span
      class="opacity-75 top-1/2 mx-auto relative flex items-center justify-center"
    >
      <Spinner />
    </span>
  </div>
{/if}
