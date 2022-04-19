<script lang="ts">
  export let isHeating: boolean = false;
</script>

<span
  class="badge text-primary-content"
  class:bg-cooling={!isHeating}
  class:bg-heating={isHeating}>{isHeating ? 'Heating' : 'Cooling'}</span
>
