<script>
  import { homeStore } from '$lib/stores/home';
  import Spinner from '$lib/components/Spinner.svelte';
</script>

<h1>Deep Heating</h1>
{#if $homeStore.connected}
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
