<script lang="ts" context="module">
  import '../app.css';

  export async function load({ fetch }) {
    const url = '/deep-heating/appsettings.json';
    const res = await fetch(url);
    if (res.ok) {
      return {
        props: {
          APPSETTINGS: await res.json(),
        },
      };
    }
    return {
      status: res.status,
      error: new Error('Could not load configuration'),
    };
  }
</script>

<script lang="ts">
  import { appSettingsStore } from '$lib/stores/appsettings';
  import Spinner from '$lib/components/Spinner.svelte';
  import { homeStore } from '$lib/stores/home';

  export let APPSETTINGS;

  // noinspection JSUnusedAssignment
  $appSettingsStore = APPSETTINGS;
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
