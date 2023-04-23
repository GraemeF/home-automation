<script lang="ts">
  import { homeStore } from '$lib/stores/home';
  import Heating from '$lib/components/Heating.svelte';
  import Room from '$lib/components/Room.svelte';
  import { compareByRoomTemperature } from '$lib/temperature';
</script>

<div class="text-sm breadcrumbs">
  <ul>
    <li><a href="/">Deep Heating</a></li>
  </ul>
</div>

<div class="mx-3.5">
  <div class="flex flex-row justify-between">
    {#if $homeStore.state}
      <Heating isHeating={$homeStore.state?.isHeating} />{/if}
  </div>
  {#if $homeStore.state}
    <div class="flex flex-row flex-wrap gap-2">
      {#each $homeStore.state?.rooms.sort(compareByRoomTemperature) as room}
        <Room {room} />
      {/each}
    </div>
  {/if}
</div>
