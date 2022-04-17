<script>
  import { homeStore } from '$lib/stores/home';
  import Spinner from '$lib/components/Spinner.svelte';
  import Heating from '$lib/components/Heating.svelte';
</script>

{#if $homeStore.connected}
  <h1>Deep Heating</h1>
  <Heating isHeating={$homeStore.state.isHeating} />
  <pre>{JSON.stringify($homeStore, null, 2)}</pre>
{:else}
  <div class="w-full h-full fixed block top-0 left-0 bg-white opacity-75 z-50">
    <span
      class="opacity-75 top-1/2 mx-auto relative flex items-center justify-center"
    >
      <Spinner />
    </span>
  </div>
{/if}
