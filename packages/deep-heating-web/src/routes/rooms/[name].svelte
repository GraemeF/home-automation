<script lang="ts">
  import { homeStore } from '$lib/stores/home';
  import Room from '$lib/components/Room.svelte';
  import { page } from '$app/stores';

  $: room = $homeStore.state?.rooms.find(
    (room) => room.name === $page.params.name
  );
</script>

<div class="text-sm breadcrumbs">
  <ul>
    <li><a href="/deep-heating">Deep Heating</a></li>
    {#if room}
      <li>{room.name}</li>
    {/if}
  </ul>
</div>
{#if room}
  <Room {room} />
  <pre>{JSON.stringify(room, null, 2)}</pre>
{:else if $homeStore.state}
  <h1>Room not found</h1>
{/if}
