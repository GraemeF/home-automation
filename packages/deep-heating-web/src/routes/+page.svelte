<script lang="ts">
  import Heating from '$lib/components/Heating.svelte';
  import Room from '$lib/components/Room.svelte';
  import { homeStore } from '$lib/stores/home';
  import { compareByRoomTemperature } from '$lib/temperature';
  import { Option, ReadonlyArray, pipe } from 'effect';
</script>

<div class="text-sm breadcrumbs">
  <ul>
    <li><a href="/">Deep Heating</a></li>
  </ul>
</div>
{#if Option.isSome($homeStore.state)}
  <div class="mx-3.5">
    <div class="flex flex-row justify-between">
      {#if Option.isSome($homeStore.state)}
        <Heating
          isHeating={pipe(
            $homeStore.state,
            Option.flatMap((state) => state.isHeating),
            Option.getOrUndefined,
          )}
        />
      {/if}
    </div>
    <div class="flex flex-row flex-wrap gap-2">
      {#each pipe( $homeStore.state.value, (state) => pipe(state.rooms, ReadonlyArray.sort(compareByRoomTemperature)), ) as room}
        <Room {room} />
      {/each}
    </div>
  </div>
{/if}
