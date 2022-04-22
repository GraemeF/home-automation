<script lang="ts">
  import type { RoomState } from '@home-automation/deep-heating-types';
  import ColderIcon from '$packages/svelte-material-icons/MinusCircleOutline.svelte';
  import ColderActiveIcon from '$packages/svelte-material-icons/MinusCircle.svelte';
  import WarmerIcon from '$packages/svelte-material-icons/PlusCircleOutline.svelte';
  import WarmerActiveIcon from '$packages/svelte-material-icons/PlusCircle.svelte';
  import { formatTemperature } from '$lib/temperature';

  const step = 0.5;
  export let room: RoomState;
  export let adjustment: number;
  export let adjust: (amount: number) => void;
</script>

{#if room.mode === 'Auto'}
  <button
    class="btn btn-circle btn-ghost btn-sm"
    on:click={() => adjust(adjustment - step)}
  >
    {#if adjustment < 0}
      <ColderActiveIcon />
    {:else}
      <ColderIcon />
    {/if}
  </button>
{/if}
<div class="grid justify-items-center">
  <p>
    {room.targetTemperature && formatTemperature(room.targetTemperature)}
  </p>
  {#if adjustment}
    <p class="stat-desc">
      {`(${formatTemperature(adjustment)})`}
    </p>
  {/if}
</div>
{#if room.mode === 'Auto'}
  <button
    class="btn btn-circle btn-ghost btn-sm"
    on:click={() => adjust(adjustment + step)}
  >
    {#if adjustment > 0}
      <WarmerActiveIcon />
    {:else}
      <WarmerIcon />
    {/if}
  </button>
{/if}
