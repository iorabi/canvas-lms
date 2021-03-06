#
# Copyright (C) 2016 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require 'spec_helper'

describe Score do
  before(:once) do
    grading_periods
    test_course.assignment_groups.create!(name: 'Assignments')
  end

  let(:test_course) { Course.create! }
  let(:student) { student_in_course(course: test_course) }
  let(:params) do
    {
      course: test_course,
      current_score: 80.2,
      final_score: 74.0,
      updated_at: 1.week.ago
    }
  end

  let(:grading_period_score_params) do
    params.merge(grading_period_id: GradingPeriod.first.id)
  end
  let(:assignment_group_score_params) do
    params.merge(assignment_group_id: AssignmentGroup.first.id)
  end
  let(:grading_period_score) { student.scores.create!(grading_period_score_params) }
  let(:assignment_group_score) { student.scores.create!(assignment_group_score_params) }

  subject_once(:score) { student.scores.create!(params) }

  it_behaves_like "soft deletion" do
    subject { student.scores }

    let(:creation_arguments) do
      [
        params.merge(grading_period: GradingPeriod.first),
        params.merge(grading_period: GradingPeriod.last)
      ]
    end
  end

  describe 'validations' do
    it { is_expected.to be_valid }

    it 'is invalid without an enrollment' do
      score.enrollment = nil
      expect(score).to be_invalid
    end

    it 'is invalid without unique enrollment for course' do
      student.scores.create!(params)
      expect { student.scores.create!(params) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'is invalid without unique enrollment for grading period' do
      student.scores.create!(grading_period_score_params)
      expect { student.scores.create!(grading_period_score_params) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it('is invalid without unique enrollment for assignment group', if: Score.course_score_populated?) do
      student.scores.create!(assignment_group_score_params)
      expect { student.scores.create!(assignment_group_score_params) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    shared_examples "score attribute" do
      it 'is valid as nil' do
        score.write_attribute(attribute, nil)
        expect(score).to be_valid
      end

      it 'is valid with a numeric value' do
        score.write_attribute(attribute, 43.2)
        expect(score).to be_valid
      end

      it 'is invalid with a non-numeric value' do
        score.write_attribute(attribute, 'dora')
        expect(score).to be_invalid
      end
    end

    include_examples('score attribute') { let(:attribute) { :current_score } }
    include_examples('score attribute') { let(:attribute) { :final_score } }

    context("scorable associations", if: Score.course_score_populated?) do
      before(:once) { grading_periods }

      it 'is valid with course_score true and no scorable associations' do
        expect(student.scores.create!(course_score: true, **params)).to be_valid
      end

      it 'is valid with course_score false and a grading period association' do
        expect(student.scores.create!(course_score: false, **grading_period_score_params)).to be_valid
      end

      it 'is valid with course_score false and an assignment group association' do
        expect(student.scores.create!(course_score: false, **assignment_group_score_params)).to be_valid
      end

      it 'is invalid with course_score false and no scorable associations' do
        expect do
          score = student.scores.create!(params)
          score.update!(course_score: false)
        end.to raise_error(ActiveRecord::RecordInvalid)
      end

      it 'is invalid with course_score true and a scorable association' do
        expect do
          student.scores.create!(course_score: true, **grading_period_score_params)
        end.to raise_error(ActiveRecord::RecordInvalid)
      end

      it 'is invalid with multiple scorable associations' do
        expect do
          student.scores.create!(grading_period_id: GradingPeriod.first.id, **assignment_group_score_params)
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe '#current_grade' do
    it 'delegates the grade conversion to the course' do
      expect(score.course).to receive(:score_to_grade).once.with(score.current_score)
      score.current_grade
    end

    it 'returns nil if grading schemes are not used in the course' do
      expect(score.course).to receive(:grading_standard_enabled?).and_return(false)
      expect(score.current_grade).to be_nil
    end

    it 'returns the grade according to the course grading scheme' do
      expect(score.course).to receive(:grading_standard_enabled?).and_return(true)
      expect(score.current_grade).to eq 'B-'
    end
  end

  describe '#final_grade' do
    it 'delegates the grade conversion to the course' do
      expect(score.course).to receive(:score_to_grade).once.with(score.final_score)
      score.final_grade
    end

    it 'returns nil if grading schemes are not used in the course' do
      expect(score.course).to receive(:grading_standard_enabled?).and_return(false)
      expect(score.final_grade).to be_nil
    end

    it 'returns the grade according to the course grading scheme' do
      expect(score.course).to receive(:grading_standard_enabled?).and_return(true)
      expect(score.final_grade).to eq 'C'
    end
  end

  describe('#scorable', if: Score.course_score_populated?) do
    it 'returns course for course score' do
      expect(score.scorable).to be score.enrollment.course
    end

    it 'returns grading period for grading period score' do
      expect(grading_period_score.scorable).to be grading_period_score.grading_period
    end

    it 'returns assignment group for assignment group score' do
      expect(assignment_group_score.scorable).to be assignment_group_score.assignment_group
    end
  end

  describe('#course_score', if: Score.course_score_populated?) do
    it 'sets course_score to true when there are no scorable associations' do
      expect(score.course_score).to be true
    end

    it 'sets course_score to false for grading period scores' do
      expect(grading_period_score.course_score).to be false
    end

    it 'sets course_score to false for assignment group scores' do
      expect(assignment_group_score.course_score).to be false
    end
  end

  describe('#params_for_course') do
    it('uses course_score', if: Score.course_score_populated?) do
      expect(Score.params_for_course).to eq(course_score: true)
    end

    it('uses nil grading period id', unless: Score.course_score_populated?) do
      expect(Score.params_for_course).to eq(grading_period_id: nil)
    end
  end

  context "permissions" do
    it "allows the proper people" do
      expect(score.grants_right?(@enrollment.user, :read)).to eq true

      teacher_in_course(active_all: true)
      expect(score.grants_right?(@teacher, :read)).to eq true
    end

    it "doesn't work for nobody" do
      expect(score.grants_right?(nil, :read)).to eq false
    end

    it "doesn't allow random classmates to read" do
      score
      student_in_course(active_all: true)
      expect(score.grants_right? @student, :read).to eq false
    end

    it "doesn't work for yourself if the course is configured badly" do
      @enrollment.course.hide_final_grade = true
      @enrollment.course.save!
      expect(score.grants_right? @enrollment.user, :read).to eq false
    end
  end
end
