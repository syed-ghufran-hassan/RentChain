<template>
  <div>
    <button @click="connectWallet">Connect Wallet</button>
    <p v-if="account">Connected: {{ account }}</p>
  </div>
</template>

<script>
export default {
  data() {
    return {
      account: null,
       name: "AppHeader", 
    };
  },
  methods: {
    async connectWallet() {
      if (window.ethereum) {
        try {
          const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
          this.account = accounts[0];
          this.$emit('account-changed', this.account);
        } catch (error) {
          console.error("User denied wallet connection", error);
        }
      } else {
        alert("Please install MetaMask or another Ethereum wallet.");
      }
    }
  }
};
</script>
