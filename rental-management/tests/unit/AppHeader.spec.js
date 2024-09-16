import { mount } from '@vue/test-utils';
import AppHeader from '@/components/AppHeader.vue';

describe('AppHeader.vue', () => {
  it('renders connect button', () => {
    const wrapper = mount(AppHeader);
    const button = wrapper.find('button');
    expect(wrapper.text()).toContain('Connect Wallet');
    expect(wrapper.text()).not.toContain('Connected:');
  });

  it('updates account when connectWallet is called', async () => {
    const wrapper = mount(AppHeader);

    // Mock the Ethereum object and its methods
    window.ethereum = {
      request: jest.fn().mockResolvedValue(['0x12345']),
    };

    // Trigger the connectWallet method
    await wrapper.vm.connectWallet();

    // Check that the account was updated
    expect(wrapper.vm.account).toBe('0x12345');
    expect(wrapper.text()).toContain('Connected: 0x12345');
  });

  it('shows an alert if no Ethereum wallet is available', async () => {
    // Mock window.ethereum as undefined
    window.ethereum = undefined;
    window.alert = jest.fn(); // Mock alert function

    const wrapper = mount(AppHeader);
    await wrapper.vm.connectWallet();

    expect(window.alert).toHaveBeenCalledWith('Please install MetaMask or another Ethereum wallet.');
  });
});
