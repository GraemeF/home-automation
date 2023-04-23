<script lang="ts">
  import '../app.css';
  import { appSettingsStore } from '$lib/stores/appsettings';
  import Spinner from '$lib/components/Spinner.svelte';
  import { homeStore } from '$lib/stores/home';
  import type { LayoutData } from './$types';

  export let data: LayoutData;

  $appSettingsStore = data;
</script>

<div class="container mx-auto">
  <slot />

  {#if !$homeStore.connected}
    <div
      class="w-full h-full fixed block top-0 left-0 bg-white opacity-75 z-50"
    >
      <span
        class="opacity-75 top-1/2 mx-auto relative flex items-center justify-center"
      >
        <Spinner />
      </span>
    </div>
  {/if}
</div>
