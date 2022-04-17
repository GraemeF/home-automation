<script>
  import { homeStore } from '$lib/stores/home';
  import Spinner from '$lib/components/Spinner.svelte';
  import Heating from '$lib/components/Heating.svelte';
  import Room from '$lib/components/Room.svelte';
</script>

{#if $homeStore.connected}
  <h1>Deep Heating</h1>
  {#if $homeStore.state}
    <Heating isHeating={$homeStore.state.isHeating} />

    <div class="stats shadow stats-vertical lg:stats-horizontal">
      {#each $homeStore.state.rooms.sort((a, b) => (a.temperature?.temperature ?? 999) - (b.temperature?.temperature ?? 999)) as room}
        <Room {room} />
      {/each}
    </div>
    <pre>{JSON.stringify($homeStore, null, 2)}</pre>
  {/if}
{:else}
  <div class="w-full h-full fixed block top-0 left-0 bg-white opacity-75 z-50">
    <span
      class="opacity-75 top-1/2 mx-auto relative flex items-center justify-center"
    >
      <Spinner />
    </span>
  </div>
{/if}
