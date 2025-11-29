<script lang="ts">
  import { formatTemperature } from '$lib/temperature';
  import ColderActiveIcon from '$packages/svelte-material-icons/MinusCircle.svelte';
  import ColderIcon from '$packages/svelte-material-icons/MinusCircleOutline.svelte';
  import WarmerActiveIcon from '$packages/svelte-material-icons/PlusCircle.svelte';
  import WarmerIcon from '$packages/svelte-material-icons/PlusCircleOutline.svelte';
  import { Schema } from 'effect';
  import {
    Temperature,
    type RoomState,
  } from '@home-automation/deep-heating-types';
  import { Option, pipe } from 'effect';

  const step = 0.5;
  export let room: RoomState;
  export let adjustment: number;
  export let adjust: (amount: number) => void;

  const isAuto = pipe(
    room.mode,
    Option.map((mode) => mode === 'Auto'),
    Option.getOrElse(() => false)
  );
</script>

{#if isAuto}
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
    {pipe(room.targetTemperature, formatTemperature)}
  </p>
  {#if adjustment}
    <p class="stat-desc">
      {`(${formatTemperature(
        Option.some(Schema.decodeUnknownSync(Temperature)(adjustment))
      )})`}
    </p>
  {/if}
</div>
{#if isAuto}
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
