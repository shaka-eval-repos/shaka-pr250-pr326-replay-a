# frozen_string_literal: true

require_relative 'repository_config_test'

class RepositoryConfigBranchesTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_loads_a_branch_name_template
    name = '{login}-{host}/{issue}-{description}'
    with_repository('branches' => { 'name' => name }) do |root|
      assert_equal name, Shaka::RepositoryConfig.load(root:).to_h.dig('branches', 'name')
    end
  end

  def test_rejects_a_branch_name_without_an_issue_placeholder
    with_repository('branches' => { 'name' => '{login}-{host}/{description}' }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, '{issue}'
    end
  end

  def test_rejects_an_unknown_branch_name_placeholder
    with_repository('branches' => { 'name' => '{jg}-{host}/{issue}-{description}' }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, 'branches.name'
    end
  end

  def test_labels_an_unknown_branch_setting
    with_repository('branches' => { 'name' => '{issue}', 'prefix' => 'feature' }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, 'unknown branches key: prefix'
    end
  end
end
