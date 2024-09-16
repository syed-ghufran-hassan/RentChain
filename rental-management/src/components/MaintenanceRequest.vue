<!-- MaintenanceRequest.vue -->
<template>
  <div>
    <h2>Submit a Maintenance Request</h2>
    <form @submit.prevent="submitRequest">
      <label for="description">Request Description:</label>
      <textarea id="description" v-model="description"></textarea>
      
      <button type="submit">Submit</button>
    </form>
  </div>
</template>

<script>
export default {
  data() {
    return {
      description: ''
    };
  },
  methods: {
    async submitRequest() {
      if (!this.description) {
        alert('Please provide a description.');
        return;
      }
      // Submit the request via smart contract or API call
      try {
        await this.contract.methods.submitMaintenanceRequest(this.description).send({ from: this.account });
        alert('Maintenance request submitted successfully.');
      } catch (error) {
        console.error('Error submitting request:', error);
        alert('There was an error submitting the request.');
      }
    }
  },
  mounted() {
    // Ensure web3 and contract are available
    if (!this.$parent.contract) {
      alert('Please connect your wallet.');
    } else {
      this.contract = this.$parent.contract;
      this.account = this.$parent.account;
    }
  }
};
</script>
