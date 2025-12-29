<script lang="ts">
  import Heating from '$lib/components/Heating.svelte';
  import Room from '$lib/components/Room.svelte';
  import { appSettingsStore } from '$lib/stores/appsettings';
  import { homeStore } from '$lib/stores/home';
  import { compareByRoomTemperature } from '$lib/temperature';
  import { Array, Option, pipe } from 'effect';

  let popOutDialog: HTMLDialogElement;
</script>

<div class="text-sm breadcrumbs">
  <ul>
    <li><a href="/">Deep Heating</a></li>
  </ul>
</div>
{#if Option.isSome($homeStore.state)}
  <div class="mx-3.5">
    <div class="flex flex-row justify-between items-center">
      {#if Option.isSome($homeStore.state)}
        <Heating
          isHeating={pipe(
            $homeStore.state,
            Option.flatMap((state) => state.isHeating),
            Option.getOrUndefined,
          )}
        />
      {/if}
      {#if $appSettingsStore?.enablePopOut}
        <button class="btn btn-primary btn-sm" onclick={() => popOutDialog.showModal()}>Pop Out</button>
      {/if}
    </div>
    <div class="flex flex-row flex-wrap gap-2">
      {#each pipe( $homeStore.state.value, (state) => pipe(state.rooms, Array.sort(compareByRoomTemperature)), ) as room (room.name)}
        <Room {room} />
      {/each}
    </div>
  </div>
{/if}

{#if $appSettingsStore?.enablePopOut}
  <dialog bind:this={popOutDialog} aria-label="Pop Out" class="modal">
    <div class="modal-box">
      <h3 class="text-lg font-bold">Popping Out</h3>
      <p class="py-4">You are currently popping out. All rooms are set to the away temperature.</p>
      <div class="modal-action">
        <form method="dialog">
          <button class="btn">Cancel</button>
        </form>
      </div>
    </div>
  </dialog>
{/if}
